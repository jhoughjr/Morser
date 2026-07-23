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

// MARK: - Scoring

/// How one character has fared across every round it has appeared in.
struct CharacterScore: Equatable {
    var attempts: Int = 0
    var hits: Int = 0
    /// Total time taken to answer, summed over the rounds that timed it. Only
    /// drills with a short enough prompt to answer by reflex record this.
    var latencyMillis: Int = 0
    var latencySamples: Int = 0

    var accuracy: Double { attempts == 0 ? 0 : Double(hits) / Double(attempts) }

    /// Seconds, or nil when this character has never been timed.
    var averageLatency: Double? {
        guard latencySamples > 0 else { return nil }
        return Double(latencyMillis) / Double(latencySamples) / 1000
    }
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
    var mode: String? { get set }
    var characterSet: String? { get set }
    var customText: String? { get set }
    var speedLadder: Bool? { get set }
}

final class UserDefaultsPracticeStore: PracticeStoring {

    private let defaults: UserDefaults
    private enum Key {
        static let level = "practice.level"
        static let charWPM = "practice.characterWPM"
        static let effWPM = "practice.effectiveWPM"
        static let scores = "practice.scores"
        static let mode = "practice.mode"
        static let characterSet = "practice.characterSet"
        static let customText = "practice.customText"
        static let speedLadder = "practice.speedLadder"
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

    var mode: String? {
        get { defaults.string(forKey: Key.mode) }
        set { defaults.set(newValue, forKey: Key.mode) }
    }

    var characterSet: String? {
        get { defaults.string(forKey: Key.characterSet) }
        set { defaults.set(newValue, forKey: Key.characterSet) }
    }

    var customText: String? {
        get { defaults.string(forKey: Key.customText) }
        set { defaults.set(newValue, forKey: Key.customText) }
    }

    var speedLadder: Bool? {
        get { defaults.object(forKey: Key.speedLadder) as? Bool }
        set { defaults.set(newValue, forKey: Key.speedLadder) }
    }

    /// Stored as [character: [attempts, hits, latencyMillis, latencySamples]] —
    /// plist-native, so no encoder.
    ///
    /// Rows written before latency existed have two elements and are read as
    /// untimed rather than discarded; nobody should lose their record to a new
    /// column.
    var scores: [Character: CharacterScore] {
        get {
            guard let raw = defaults.dictionary(forKey: Key.scores) as? [String: [Int]] else { return [:] }
            var result: [Character: CharacterScore] = [:]
            for (key, row) in raw {
                guard let char = key.first, row.count >= 2 else { continue }
                result[char] = CharacterScore(attempts: row[0],
                                              hits: row[1],
                                              latencyMillis: row.count > 2 ? row[2] : 0,
                                              latencySamples: row.count > 3 ? row[3] : 0)
            }
            return result
        }
        set {
            let raw = newValue.reduce(into: [String: [Int]]()) { acc, entry in
                acc[String(entry.key)] = [entry.value.attempts, entry.value.hits,
                                          entry.value.latencyMillis, entry.value.latencySamples]
            }
            defaults.set(raw, forKey: Key.scores)
        }
    }
}

// MARK: - Session

final class PracticeSession: ObservableObject {

    /// The Koch ladder. It belongs to the drill that walks it; this stays for
    /// the callers that ask the session how long the ladder is.
    static var kochOrder: [Character] { KochDrill.order }

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
    /// How well-formed the sending was, for drills you key rather than copy.
    @Published private(set) var fistReport: FistReport?
    @Published private(set) var scores: [Character: CharacterScore] = [:]

    @Published var groupSize: Int = 5
    @Published var groupCount: Int = 5

    @Published var mode: PracticeMode = .koch {
        didSet {
            guard mode != oldValue else { return }
            store.mode = mode.rawValue
            // A prompt built by the previous drill would be marked by the new
            // one's rules, so the round ends with the mode.
            prompt = ""
            answer = ""
            grade = nil
            phase = .ready
        }
    }

    @Published var characterSet: CharacterSetChoice = .letters {
        didSet { store.characterSet = characterSet.rawValue }
    }

    @Published var customText: String = "the quick brown fox jumps over the lazy dog" {
        didSet { store.customText = customText }
    }

    /// Raise the character speed automatically once you can hold the pace.
    /// Deciding when to speed up is exactly the judgement a learner doesn't have
    /// yet, and the usual failure is leaving it too low for months.
    @Published var speedLadder: Bool = false {
        didSet { store.speedLadder = speedLadder }
    }

    /// Consecutive clean rounds that earn one more word per minute.
    static let ladderStreak = 3
    static let maximumWPM: Double = 40

    /// When the sending finished, for drills that time the answer.
    private var sentAt: Date?
    /// The most recent answer time, in seconds.
    @Published private(set) var lastLatency: Double?

    var answerMethod: AnswerMethod { drill.answerMethod }
    var answerDeadline: TimeInterval? { drill.answerDeadline }

    var drill: any PracticeDrill { mode.drill }

    private var context: DrillContext {
        DrillContext(level: level,
                     scores: scores,
                     groupSize: groupSize,
                     groupCount: groupCount,
                     customText: customText,
                     characterSet: characterSet,
                     randomIndex: randomIndex)
    }

    /// This sitting only — the per-character record is what persists. Kept apart
    /// so a good run today isn't hidden by a bad week.
    @Published private(set) var roundsThisSession = 0
    @Published private(set) var sessionHits = 0
    @Published private(set) var sessionTotal = 0
    /// Consecutive rounds at or above the threshold.
    @Published private(set) var streak = 0

    var sessionAccuracy: Double {
        sessionTotal == 0 ? 0 : Double(sessionHits) / Double(sessionTotal)
    }

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
        self.mode = store.mode.flatMap(PracticeMode.init(rawValue:)) ?? .koch
        self.characterSet = store.characterSet.flatMap(CharacterSetChoice.init(rawValue:)) ?? .letters
        self.customText = store.customText ?? "the quick brown fox jumps over the lazy dog"
        self.speedLadder = store.speedLadder ?? false
    }

    // MARK: Alphabet

    /// The characters in play. Empty when the drill has no fixed alphabet —
    /// callsigns and QSO text draw on the whole mode.
    var alphabet: [Character] {
        drill.alphabet(context)
    }

    /// The character unlocked by advancing, or nil when there's no ladder to walk.
    var nextCharacter: Character? {
        guard drill.usesLevels, level < Self.kochOrder.count else { return nil }
        return Self.kochOrder[level]
    }

    // MARK: Timing

    var ditTime: Double { Morse.Timing.ditTime(wpm: characterWPM) }
    var spaceDitTime: Double {
        Morse.Timing.farnsworthSpaceDitTime(characterWPM: characterWPM, effectiveWPM: effectiveWPM)
    }

    // MARK: Rounds

    /// Exposed for the Koch drill's weighting, which is the one piece of prompt
    /// selection worth being able to look at from outside.
    var weightedBag: [Character] {
        KochDrill().weightedBag(context)
    }

    /// Builds a fresh prompt and clears the previous answer.
    func startRound() {
        let text = drill.makePrompt(context)
        guard !text.isEmpty else {
            prompt = ""
            phase = .ready
            return
        }

        prompt = text
        answer = ""
        grade = nil
        fistReport = nil

        // Nothing is played for a drill you send: the prompt is on screen and
        // the round starts the moment it appears.
        phase = drill.answerMethod == .keyed ? .answering : .sending
        if phase == .answering { sentAt = Date() }
    }

    /// Grades a keyed round by reading the timings back.
    @discardableResult
    func submitKeyed(presses: [Press]) -> Grade {
        fistReport = FistReport.measure(presses)
        answer = FistDecoder.decode(presses).text
        return submit()
    }

    /// The prompt as morse, ready for the conductor.
    var promptMorse: String { Morse.morse(from: prompt) }

    /// Called when the audio has finished; the copy is only accepted afterwards
    /// so nobody can type along with the sending.
    func finishedSending() {
        guard phase == .sending else { return }
        phase = .answering
        sentAt = Date()
    }

    /// Sends the same prompt again — the copy so far is kept.
    func replay() {
        guard phase == .answering || phase == .sending, !prompt.isEmpty else { return }
        phase = .sending
    }

    /// Grades `answer` against `prompt` and folds the result into the running scores.
    /// Grades the round.
    /// - Parameter selfReported: for head copy, where there is nothing to compare
    ///   against but your own answer. `nil` grades the typed copy.
    @discardableResult
    func submit(selfReported: Bool? = nil) -> Grade {
        let result = selfReported.map { Self.selfReportedGrade(prompt: prompt, copied: $0) }
            ?? Self.grade(prompt: prompt, answer: answer)
        grade = result
        phase = .graded

        let latency = sentAt.map { Date().timeIntervalSince($0) }
        lastLatency = drill.measuresLatency ? latency : nil
        sentAt = nil

        for cell in result.cells {
            guard let expected = cell.expected else { continue }
            var score = scores[expected] ?? CharacterScore()
            score.attempts += 1
            if cell.isHit { score.hits += 1 }
            // Only time a hit. How long it took to get it wrong isn't a speed.
            if let latency, drill.measuresLatency, cell.isHit {
                score.latencyMillis += Int(latency * 1000)
                score.latencySamples += 1
            }
            scores[expected] = score
        }
        store.scores = scores

        roundsThisSession += 1
        sessionHits += result.hits
        sessionTotal += result.total
        streak = result.accuracy >= Self.advanceThreshold ? streak + 1 : 0

        if speedLadder, streak >= Self.ladderStreak, characterWPM < Self.maximumWPM {
            characterWPM = min(characterWPM + 1, Self.maximumWPM)
            // The streak was earned at the old speed and says nothing about the new one.
            streak = 0
        }

        return result
    }

    var canAdvance: Bool {
        guard drill.usesLevels, phase == .graded, let grade else { return false }
        return grade.accuracy >= Self.advanceThreshold && level < Self.kochOrder.count
    }

    /// The most recently unlocked character — the one still being learned.
    var newestCharacter: Character? { alphabet.last }

    func advance() {
        guard drill.usesLevels, level < Self.kochOrder.count else { return }
        level += 1
        // The streak was earned on the old alphabet; it says nothing about the new one.
        streak = 0
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

    /// Splits into groups, and drops the angle brackets a prosign is written
    /// with — nobody types `<AR>` under time pressure, and the brackets are
    /// notation for us rather than something that goes over the air.
    /// A grade from a yes or no.
    ///
    /// Head copy has nothing to compare against, so the whole prompt stands or
    /// falls together — which is honest: hearing four letters of a five-letter
    /// word is not having copied it.
    static func selfReportedGrade(prompt: String, copied: Bool) -> Grade {
        Grade(groups: groups(in: prompt).map { group in
            group.map { Grade.Cell(expected: $0, heard: copied ? $0 : nil) }
        })
    }

    private static func groups(in text: String) -> [[Character]] {
        text.uppercased()
            .split(whereSeparator: { $0.isWhitespace })
            .map { Array($0.filter { $0 != "<" && $0 != ">" }) }
            .filter { !$0.isEmpty }
    }
}
