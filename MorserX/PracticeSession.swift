//
//  PracticeSession.swift
//  MorserX
//
//  Copy practice, by the Koch method: you start with two characters at full
//  speed and add a third only once you can copy the first two. The alternative —
//  learning the whole alphabet slowly and speeding up — teaches you to count
//  dits, which is a habit you then have to unlearn. So speed is never the
//  variable here; the size of the alphabet is.
//
//  Everything in this file is view-free on purpose. Generation, grading and
//  progression are the parts that can be wrong in ways you wouldn't notice by
//  looking at the screen, so they're testable without one.
//

import Foundation
import Morse

// MARK: - Speed

/// Character speed and effective speed, and the spacing that reconciles them.
///
/// Farnsworth timing sends each character at full speed but pads the gaps, so a
/// beginner hears the real rhythm of a letter — which is the thing being learned —
/// with time to write it down.
enum Farnsworth {

    /// PARIS-standard dit length for a given words-per-minute.
    static func ditTime(wpm: Double) -> Double {
        guard wpm > 0 else { return 0.1 }
        return 1.2 / wpm
    }

    /// The dit length that the *spaces* are measured in, per the ARRL formula.
    ///
    /// At `effectiveWPM == characterWPM` this reduces exactly to `ditTime(wpm:)`,
    /// which is the property that keeps a non-Farnsworth session honest rather
    /// than merely close.
    static func spaceDitTime(characterWPM c: Double, effectiveWPM s: Double) -> Double {
        guard c > 0, s > 0 else { return ditTime(wpm: max(c, 1)) }
        // Never send the spacing faster than the characters.
        let effective = min(s, c)
        let ta = (60 * c - 37.2 * effective) / (c * effective)
        return ta / 19
    }

    /// Words per minute implied by a dit length, for labelling an existing slider.
    static func wpm(ditTime: Double) -> Double {
        guard ditTime > 0 else { return 0 }
        return 1.2 / ditTime
    }
}

// MARK: - Scoring

/// How one character has fared across every round it has appeared in.
struct CharacterScore: Equatable {
    var attempts: Int = 0
    var hits: Int = 0

    var accuracy: Double { attempts == 0 ? 0 : Double(hits) / Double(attempts) }
}

/// The result of comparing what was sent with what was heard.
struct Grade: Equatable {

    /// One sent character and whatever landed in its place.
    struct Cell: Equatable {
        let expected: Character?
        let heard: Character?

        var isHit: Bool { expected != nil && expected == heard }
        /// Typed something that wasn't sent — the group ran long.
        var isExtra: Bool { expected == nil && heard != nil }
        /// Sent but nothing typed there.
        var isMissed: Bool { expected != nil && heard == nil }
    }

    let groups: [[Cell]]

    var cells: [Cell] { groups.flatMap { $0 } }
    var total: Int { cells.filter { $0.expected != nil }.count }
    var hits: Int { cells.filter { $0.isHit }.count }
    var accuracy: Double { total == 0 ? 0 : Double(hits) / Double(total) }
}

// MARK: - Persistence

/// What survives quitting the app: which level you reached and how each
/// character has been treating you.
protocol PracticeStoring: AnyObject {
    var level: Int? { get set }
    var characterWPM: Double? { get set }
    var effectiveWPM: Double? { get set }
    var scores: [Character: CharacterScore] { get set }
}

final class UserDefaultsPracticeStore: PracticeStoring {

    private let defaults: UserDefaults
    private enum Key {
        static let level = "practice.level"
        static let charWPM = "practice.characterWPM"
        static let effWPM = "practice.effectiveWPM"
        static let scores = "practice.scores"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var level: Int? {
        get { defaults.object(forKey: Key.level) as? Int }
        set { defaults.set(newValue, forKey: Key.level) }
    }

    var characterWPM: Double? {
        get { defaults.object(forKey: Key.charWPM) as? Double }
        set { defaults.set(newValue, forKey: Key.charWPM) }
    }

    var effectiveWPM: Double? {
        get { defaults.object(forKey: Key.effWPM) as? Double }
        set { defaults.set(newValue, forKey: Key.effWPM) }
    }

    /// Stored as [character: [attempts, hits]] — plist-native, so no encoder and
    /// no migration the first time the shape changes.
    var scores: [Character: CharacterScore] {
        get {
            guard let raw = defaults.dictionary(forKey: Key.scores) as? [String: [Int]] else { return [:] }
            var result: [Character: CharacterScore] = [:]
            for (key, pair) in raw {
                guard let char = key.first, pair.count == 2 else { continue }
                result[char] = CharacterScore(attempts: pair[0], hits: pair[1])
            }
            return result
        }
        set {
            let raw = newValue.reduce(into: [String: [Int]]()) { acc, entry in
                acc[String(entry.key)] = [entry.value.attempts, entry.value.hits]
            }
            defaults.set(raw, forKey: Key.scores)
        }
    }
}

// MARK: - Session

final class PracticeSession: ObservableObject {

    /// Koch's order: characters that are easy to confuse arrive close together,
    /// so you're forced to hear the difference early instead of building a habit
    /// that later has to break.
    static let kochOrder = Array("KMRSUAPTLOWI.NJEF0Y,VG5/Q9ZH38B?427C1D6X")

    static let minimumLevel = 2
    /// Accuracy at which the next character is unlocked. The conventional bar.
    static let advanceThreshold = 0.9

    enum Phase: Equatable {
        case ready       // nothing sent yet this round
        case sending     // audio is playing
        case answering   // sent; waiting on the copy
        case graded
    }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var prompt: String = ""
    @Published var answer: String = ""
    @Published private(set) var grade: Grade?
    @Published private(set) var scores: [Character: CharacterScore] = [:]

    @Published var groupSize: Int = 5
    @Published var groupCount: Int = 5

    @Published var level: Int = PracticeSession.minimumLevel {
        didSet {
            let clamped = min(max(level, Self.minimumLevel), Self.kochOrder.count)
            if clamped != level { level = clamped; return }
            store.level = level
        }
    }

    @Published var characterWPM: Double = 18 {
        didSet {
            if effectiveWPM > characterWPM { effectiveWPM = characterWPM }
            store.characterWPM = characterWPM
        }
    }

    @Published var effectiveWPM: Double = 10 {
        didSet { store.effectiveWPM = effectiveWPM }
    }

    /// Injected so a test can make the "random" prompt an argument rather than
    /// something to work around.
    var randomIndex: (Int) -> Int = { Int.random(in: 0..<max($0, 1)) }

    private let store: PracticeStoring

    init(store: PracticeStoring = UserDefaultsPracticeStore()) {
        self.store = store
        self.level = store.level.map { min(max($0, Self.minimumLevel), Self.kochOrder.count) } ?? Self.minimumLevel
        self.characterWPM = store.characterWPM ?? 18
        self.effectiveWPM = min(store.effectiveWPM ?? 10, self.characterWPM)
        self.scores = store.scores
    }

    // MARK: Alphabet

    /// The characters in play at the current level.
    var alphabet: [Character] {
        Array(Self.kochOrder.prefix(level))
    }

    /// The character unlocked by advancing, or nil at the top of the ladder.
    var nextCharacter: Character? {
        level < Self.kochOrder.count ? Self.kochOrder[level] : nil
    }

    // MARK: Timing

    var ditTime: Double { Farnsworth.ditTime(wpm: characterWPM) }
    var spaceDitTime: Double { Farnsworth.spaceDitTime(characterWPM: characterWPM, effectiveWPM: effectiveWPM) }

    // MARK: Rounds

    /// Builds a fresh prompt and clears the previous answer.
    func startRound() {
        let letters = alphabet
        guard !letters.isEmpty, groupSize > 0, groupCount > 0 else {
            prompt = ""
            phase = .ready
            return
        }

        prompt = (0..<groupCount)
            .map { _ in
                String((0..<groupSize).map { _ in
                    let index = min(max(randomIndex(letters.count), 0), letters.count - 1)
                    return letters[index]
                })
            }
            .joined(separator: " ")

        answer = ""
        grade = nil
        phase = .sending
    }

    /// The prompt as morse, ready for the conductor.
    var promptMorse: String { Morse.morse(from: prompt) }

    /// Called when the audio has finished; the copy is only accepted afterwards
    /// so nobody can type along with the sending.
    func finishedSending() {
        guard phase == .sending else { return }
        phase = .answering
    }

    /// Sends the same prompt again — the copy so far is kept.
    func replay() {
        guard phase == .answering || phase == .sending, !prompt.isEmpty else { return }
        phase = .sending
    }

    /// Grades `answer` against `prompt` and folds the result into the running scores.
    @discardableResult
    func submit() -> Grade {
        let result = Self.grade(prompt: prompt, answer: answer)
        grade = result
        phase = .graded

        for cell in result.cells {
            guard let expected = cell.expected else { continue }
            var score = scores[expected] ?? CharacterScore()
            score.attempts += 1
            if cell.isHit { score.hits += 1 }
            scores[expected] = score
        }
        store.scores = scores

        return result
    }

    var canAdvance: Bool {
        guard phase == .graded, let grade else { return false }
        return grade.accuracy >= Self.advanceThreshold && level < Self.kochOrder.count
    }

    func advance() {
        guard level < Self.kochOrder.count else { return }
        level += 1
    }

    func retreat() {
        guard level > Self.minimumLevel else { return }
        level -= 1
    }

    func resetScores() {
        scores = [:]
        store.scores = scores
    }

    /// Characters worth drilling: attempted at least once, worst first.
    var weakest: [(character: Character, score: CharacterScore)] {
        alphabet
            .compactMap { char in scores[char].map { (char, $0) } }
            .filter { $0.1.attempts > 0 }
            .sorted { $0.1.accuracy < $1.1.accuracy }
    }

    // MARK: Grading

    /// Compares sent against copied, group by group.
    ///
    /// Alignment is per group rather than across the whole prompt: dropping one
    /// character shouldn't mark every character after it wrong, which is what a
    /// single positional comparison of the full string would do.
    static func grade(prompt: String, answer: String) -> Grade {
        let sent = groups(in: prompt)
        let heard = groups(in: answer)

        let groupCount = max(sent.count, heard.count)
        var built: [[Grade.Cell]] = []

        for i in 0..<groupCount {
            let expected = i < sent.count ? sent[i] : []
            let copied = i < heard.count ? heard[i] : []
            let width = max(expected.count, copied.count)

            built.append((0..<width).map { j in
                Grade.Cell(expected: j < expected.count ? expected[j] : nil,
                           heard: j < copied.count ? copied[j] : nil)
            })
        }

        return Grade(groups: built)
    }

    private static func groups(in text: String) -> [[Character]] {
        text.uppercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { Array($0) }
    }
}
