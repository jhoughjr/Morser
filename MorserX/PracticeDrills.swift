//
//  PracticeDrills.swift
//  MorserX
//
//  What gets sent, and out of what alphabet.
//
//  Everything else about practice — the sending, Farnsworth spacing, the marking,
//  the per-character record — is the same whatever you're copying. A drill is
//  only the part that differs: which characters are in play, and how they're
//  arranged into a prompt.
//

import Foundation
import Morse

// MARK: - Context

/// What a drill is allowed to know about the session asking for a prompt.
struct DrillContext {
    var level: Int = 2
    var scores: [Character: CharacterScore] = [:]
    var groupSize: Int = 5
    var groupCount: Int = 5
    var customText: String = ""
    var characterSet: CharacterSetChoice = .letters

    /// Picks an index in `0..<count`. Injected so a test can make the "random"
    /// prompt an argument rather than something to work around.
    var randomIndex: (Int) -> Int = { Int.random(in: 0..<max($0, 1)) }

    func pick<T>(from items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[min(max(randomIndex(items.count), 0), items.count - 1)]
    }
}

/// The character groups a set-filter drill can work from.
enum CharacterSetChoice: String, CaseIterable, Identifiable, Sendable {
    case letters, digits, punctuation, alphanumeric, weakest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .letters:      return "Letters"
        case .digits:       return "Numbers"
        case .punctuation:  return "Punctuation"
        case .alphanumeric: return "Letters + numbers"
        case .weakest:      return "My worst"
        }
    }

    func characters(scores: [Character: CharacterScore]) -> [Character] {
        switch self {
        case .letters:      return Morse.Alphabet.letters.characters
        case .digits:       return Morse.Alphabet.digits.characters
        case .punctuation:  return Morse.Alphabet.punctuation.characters
        case .alphanumeric: return Morse.Alphabet.letters.characters + Morse.Alphabet.digits.characters
        case .weakest:
            // Worst first, and only what's actually been heard — there's nothing
            // to be worst at otherwise.
            let attempted = scores.filter { $0.value.attempts > 0 }
                .sorted { $0.value.accuracy < $1.value.accuracy }
                .map(\.key)
            return attempted.isEmpty ? Morse.Alphabet.letters.characters : Array(attempted.prefix(8))
        }
    }
}

// MARK: - Drill

/// How a round is answered. The drill decides, because it's the drill that
/// knows whether writing the answer down is part of the skill or in the way of it.
enum AnswerMethod: Sendable {
    /// Type what you heard, then Return.
    case typed
    /// Say whether you got it. Head copy is ruined by a text field — the point
    /// is to stop writing.
    case selfReported
    /// One key, no Return. Anything slower than a reflex isn't recognition.
    case singleKey
}

enum PracticeMode: String, CaseIterable, Identifiable, Sendable {
    case koch, characterSet, callsigns, qso, words, headCopy, instant, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .koch:         return "Koch"
        case .characterSet: return "Character set"
        case .callsigns:    return "Callsigns"
        case .qso:          return "QSO"
        case .words:        return "Words"
        case .headCopy:     return "Head copy"
        case .instant:      return "Instant"
        case .custom:       return "My text"
        }
    }

    var summary: String {
        switch self {
        case .koch:         return "Two characters at full speed, one more each time you can copy them"
        case .characterSet: return "Groups drawn from one part of the mode"
        case .callsigns:    return "Prefix, digit, suffix — the shape real calls have"
        case .qso:          return "What actually goes over the air, prosigns included"
        case .words:        return "Whole words, heard as one shape rather than spelled out"
        case .headCopy:     return "One word, nothing to write on — did you get it?"
        case .instant:      return "One character against the clock; the metric is how fast, not just whether"
        case .custom:       return "Whatever you paste in"
        }
    }

    var drill: any PracticeDrill {
        switch self {
        case .koch:         return KochDrill()
        case .characterSet: return CharacterSetDrill()
        case .callsigns:    return CallsignDrill()
        case .qso:          return QSODrill()
        case .words:        return WordsDrill()
        case .headCopy:     return HeadCopyDrill()
        case .instant:      return InstantDrill()
        case .custom:       return CustomTextDrill()
        }
    }
}

protocol PracticeDrill {
    var mode: PracticeMode { get }
    /// Whether the Koch ladder (level, unlock, next character) applies.
    var usesLevels: Bool { get }
    var answerMethod: AnswerMethod { get }
    /// Seconds allowed to answer, or nil for no clock.
    var answerDeadline: TimeInterval? { get }
    /// Whether how *long* the answer took is worth recording. It only means
    /// something when the prompt is short enough to answer by reflex.
    var measuresLatency: Bool { get }
    /// The characters in play, for display. Empty when the idea doesn't apply.
    func alphabet(_ context: DrillContext) -> [Character]
    /// The text to send, as space-separated groups.
    func makePrompt(_ context: DrillContext) -> String
}

extension PracticeDrill {
    var usesLevels: Bool { false }
    var answerMethod: AnswerMethod { .typed }
    var answerDeadline: TimeInterval? { nil }
    var measuresLatency: Bool { false }
    func alphabet(_ context: DrillContext) -> [Character] { [] }
}

// MARK: - Koch

struct KochDrill: PracticeDrill {
    let mode = PracticeMode.koch
    let usesLevels = true

    /// Koch's order: characters that are easy to confuse arrive close together,
    /// so you're forced to hear the difference early instead of building a habit
    /// that later has to break.
    static let order = Array("KMRSUAPTLOWI.NJEF0Y,VG5/Q9ZH38B?427C1D6X")

    func alphabet(_ context: DrillContext) -> [Character] {
        Array(Self.order.prefix(min(max(context.level, 2), Self.order.count)))
    }

    /// How often each character should turn up, expressed as copies in a bag.
    ///
    /// A flat draw spends most of a round on characters you already know. The one
    /// you just unlocked is the one you can't copy yet, so it gets the most; after
    /// that, weight follows failure. Everything keeps at least one copy —
    /// drilling only the weak ones would let the strong ones rot.
    func weightedBag(_ context: DrillContext) -> [Character] {
        let letters = alphabet(context)
        guard let newest = letters.last else { return [] }

        return letters.flatMap { character -> [Character] in
            var copies = 2
            if character == newest { copies += 3 }
            if let score = context.scores[character], score.attempts >= 5 {
                copies += Int(((1 - score.accuracy) * 4).rounded())
            }
            return Array(repeating: character, count: copies)
        }
    }

    func makePrompt(_ context: DrillContext) -> String {
        groups(from: weightedBag(context), context: context)
    }
}

// MARK: - Character set

struct CharacterSetDrill: PracticeDrill {
    let mode = PracticeMode.characterSet

    func alphabet(_ context: DrillContext) -> [Character] {
        context.characterSet.characters(scores: context.scores)
    }

    func makePrompt(_ context: DrillContext) -> String {
        groups(from: alphabet(context), context: context)
    }
}

// MARK: - Callsigns

/// Callsigns have a shape — one or two prefix letters, sometimes a digit inside
/// the prefix, then a separating digit, then a short suffix. Copying that shape
/// is a different skill from copying uniform random groups: you start predicting,
/// which is most of what copying at speed actually is.
struct CallsignDrill: PracticeDrill {
    let mode = PracticeMode.callsigns

    static let singleLetterPrefixes = ["K", "N", "W"]
    static let twoLetterPrefixes = ["AA", "KB", "WA", "VE", "VA", "DL", "DK", "GM", "GW",
                                    "JA", "JH", "EA", "SM", "OH", "LA", "PA", "ON", "OK",
                                    "SP", "YO", "LZ", "UA", "ZL", "VK", "ZS", "PY", "LU"]

    func makePrompt(_ context: DrillContext) -> String {
        (0..<max(context.groupCount, 1))
            .map { _ in callsign(context) }
            .joined(separator: " ")
    }

    private func callsign(_ context: DrillContext) -> String {
        let useSingle = context.randomIndex(3) == 0
        let prefix = useSingle
            ? (context.pick(from: Self.singleLetterPrefixes) ?? "K")
            : (context.pick(from: Self.twoLetterPrefixes) ?? "AA")

        let digit = Morse.Alphabet.digits.characters
        let separator = context.pick(from: digit).map(String.init) ?? "1"

        let letters = Morse.Alphabet.letters.characters
        let suffixLength = 1 + context.randomIndex(3)   // 1…3
        let suffix = (0..<suffixLength)
            .compactMap { _ in context.pick(from: letters).map(String.init) }
            .joined()

        return prefix + separator + suffix
    }
}

// MARK: - QSO

/// The on-air vocabulary is small and endlessly repeated, which is exactly why
/// it's learnable as whole chunks rather than letter by letter.
struct QSODrill: PracticeDrill {
    let mode = PracticeMode.qso

    static let phrases = [
        "CQ CQ DE", "DE", "UR RST", "RST 599 599", "QTH", "NAME", "OP",
        "TU", "73", "88", "QSL", "QRZ", "QRM", "QRN", "QSY", "QRS", "QRQ",
        "PSE K", "R R", "FB", "HR", "WX", "ANT", "PWR", "RIG", "AGN",
        "GM", "GA", "GE", "<AR>", "<SK>", "<BT>", "<KN>", "<AS>"
    ]

    func makePrompt(_ context: DrillContext) -> String {
        (0..<max(context.groupCount, 1))
            .map { _ in context.pick(from: Self.phrases) ?? "TU" }
            .joined(separator: " ")
    }
}

// MARK: - Custom

struct CustomTextDrill: PracticeDrill {
    let mode = PracticeMode.custom

    /// Sent a few words at a time. Pasting a paragraph and sending all of it
    /// would be one unmarkable round.
    func makePrompt(_ context: DrillContext) -> String {
        let words = context.customText
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !words.isEmpty else { return "" }

        let wanted = max(context.groupCount, 1)
        guard words.count > wanted else { return words.joined(separator: " ") }

        let start = min(context.randomIndex(words.count - wanted + 1), words.count - wanted)
        return words[start..<(start + wanted)].joined(separator: " ")
    }
}

// MARK: - Words

/// Whole words, so `THE` becomes one shape instead of three letters.
///
/// This is the bridge to head copy: you cannot hold a word in your head until
/// you stop hearing it as a spelling.
struct WordsDrill: PracticeDrill {
    let mode = PracticeMode.words

    /// Mostly plain English, with enough on-air vocabulary that the words you'll
    /// meet most often on the air turn up here too.
    static func vocabulary(_ context: DrillContext) -> [String] {
        CommonWords.english + CommonWords.radio
    }

    func makePrompt(_ context: DrillContext) -> String {
        let words = Self.vocabulary(context)
        return (0..<max(context.groupCount, 1))
            .compactMap { _ in context.pick(from: words) }
            .joined(separator: " ")
    }
}

// MARK: - Head copy

/// One word, no text field, and then you say whether you got it.
///
/// Writing while you listen is the habit that caps most people around 20 wpm,
/// and it can't be unlearned while there's somewhere to write.
struct HeadCopyDrill: PracticeDrill {
    let mode = PracticeMode.headCopy
    let answerMethod = AnswerMethod.selfReported

    func makePrompt(_ context: DrillContext) -> String {
        let words = WordsDrill.vocabulary(context)
        // One word. Two would be a memory test rather than a copying one.
        return context.pick(from: words) ?? "the"
    }
}

// MARK: - Instant recognition

/// One character against the clock.
///
/// The metric here is latency, not accuracy: at speed, "right after two seconds
/// of thinking" is a miss, and a drill that only counts correctness would call
/// it a pass and tell you nothing.
struct InstantDrill: PracticeDrill {
    let mode = PracticeMode.instant
    let usesLevels = true
    let answerMethod = AnswerMethod.singleKey
    let measuresLatency = true
    var answerDeadline: TimeInterval? { 3 }

    func alphabet(_ context: DrillContext) -> [Character] {
        KochDrill().alphabet(context)
    }

    func makePrompt(_ context: DrillContext) -> String {
        guard let character = context.pick(from: KochDrill().weightedBag(context)) else { return "" }
        return String(character)
    }
}

// MARK: - Shared

private extension PracticeDrill {
    /// Random groups of a fixed size, the shape every set-based drill wants.
    func groups(from characters: [Character], context: DrillContext) -> String {
        guard !characters.isEmpty, context.groupSize > 0, context.groupCount > 0 else { return "" }

        return (0..<context.groupCount)
            .map { _ in
                String((0..<context.groupSize).compactMap { _ in context.pick(from: characters) })
            }
            .joined(separator: " ")
    }
}
