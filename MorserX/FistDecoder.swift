//
//  FistDecoder.swift
//  MorserX
//
//  Reading back what the operator actually sent.
//
//  Almost every trainer marks you on the text you produced. That hides the thing
//  most worth knowing: whether your *fist* is readable. You can send GAT instead
//  of CAT and know it instantly; you cannot hear that your dahs are only twice
//  your dits, because to you they sound like dahs. Nobody else can read that.
//
//  So this decodes from the timings rather than from symbols the app generated,
//  and reports the ratios alongside the text. It is a pure function over an array
//  of press durations — no audio, no UI, and therefore testable against a fist
//  that never has to exist.
//

import Foundation
import Morse

// MARK: - What was keyed

/// One press of the key: when it went down, and for how long.
struct Press: Equatable, Sendable {
    /// Seconds since the first key-down of this transmission.
    let start: Double
    let duration: Double

    var end: Double { start + duration }
}

/// Collects presses as they happen.
///
/// Split out from the keyer so the recording can be tested without an audio
/// engine, and so a replay can be fed in from anywhere.
struct FistRecorder {
    private(set) var presses: [Press] = []
    private var origin: Double?
    private var pressStart: Double?

    var isKeyDown: Bool { pressStart != nil }

    mutating func down(at time: Double) {
        guard pressStart == nil else { return }
        if origin == nil { origin = time }
        pressStart = time
    }

    mutating func up(at time: Double) {
        guard let start = pressStart, let origin else { return }
        pressStart = nil
        let duration = max(0, time - start)
        guard duration > 0 else { return }
        presses.append(Press(start: start - origin, duration: duration))
    }

    mutating func reset() {
        presses = []
        origin = nil
        pressStart = nil
    }
}

// MARK: - Decoding

enum FistDecoder {

    /// What one press or gap was taken to be.
    enum Element: Equatable, Sendable {
        case dit, dah
        case intraGap, letterGap, wordGap
    }

    struct Result: Equatable, Sendable {
        let text: String
        let morse: String
        let elements: [Element]
        /// The dit length this reading was measured against, in seconds.
        let ditSeconds: Double
        /// True when the presses were all so alike that dit and dah can't be
        /// told apart. They're read as dits, but that's a guess, not a reading.
        let isAmbiguous: Bool
        /// Symbol groups that spell nothing in the mode.
        ///
        /// This is what running your letters together looks like from the
        /// outside: the gap falls below a letter gap, the symbols merge, and the
        /// result is a code no character has. Without counting these the report
        /// has nothing to say about the fault — the letter gaps it would have
        /// measured were swallowed into the characters.
        let unreadableGroups: Int

        static let empty = Result(text: "", morse: "", elements: [],
                                  ditSeconds: 0, isAmbiguous: false, unreadableGroups: 0)
    }

    /// Below this ratio between the long and short groups, there is no contrast
    /// to read: a string of identical presses is identical whether they were all
    /// meant as dits or all as dahs.
    static let minimumContrast = 1.8

    static func decode(_ presses: [Press]) -> Result {
        guard !presses.isEmpty else { return .empty }

        let durations = presses.map(\.duration)
        let (shortGroup, longGroup, ambiguous) = split(durations)

        // The dit is the short group's centre. Taking the minimum instead would
        // let one clipped press define the timebase for the whole transmission.
        let dit = shortGroup.isEmpty ? (longGroup.reduce(0, +) / Double(longGroup.count)) / 3
                                     : shortGroup.reduce(0, +) / Double(shortGroup.count)
        guard dit > 0 else { return .empty }

        // The boundary sits between the two groups the presses actually fell
        // into, not at a fixed multiple of the dit. A fixed rule would undo the
        // clustering: someone whose dahs run at twice their dits — the commonest
        // fault there is — would have every dah read back as a dit, and be told
        // their text was wrong rather than their timing.
        let dahThreshold = longGroup.isEmpty
            ? dit * 2
            : (dit + longGroup.reduce(0, +) / Double(longGroup.count)) / 2

        var elements: [Element] = []
        var morse = ""
        var previous: Press?

        for press in presses {
            if let previous {
                let gap = press.start - previous.end
                let element = classify(gap: gap, dit: dit)
                elements.append(element)
                switch element {
                case .letterGap: morse += Morse.Symbols.letterSpace.rawValue
                case .wordGap:   morse += Morse.Symbols.wordSpace.rawValue
                default:         break
                }
            }

            let isDah = !ambiguous && press.duration > dahThreshold
            elements.append(isDah ? .dah : .dit)
            morse += isDah ? Morse.Symbols.dah.rawValue : Morse.Symbols.dit.rawValue
            previous = press
        }

        return Result(text: Morse.decode(morse),
                      morse: morse,
                      elements: elements,
                      ditSeconds: dit,
                      isAmbiguous: ambiguous,
                      unreadableGroups: unreadableGroups(in: morse))
    }

    /// Groups that spell nothing — the signature of run-together letters.
    static func unreadableGroups(in morse: String) -> Int {
        Morse.morseWords(from: morse)
            .flatMap { $0.split(separator: Morse.Symbols.letterSpace.rawValue) }
            .filter { group in
                let code = String(group)
                return Morse.character(for: code) == nil && Morse.Prosign.allCases.allSatisfy { $0.code != code }
            }
            .count
    }

    /// Gaps are 1, 3 and 7 dits. The boundaries sit between those, not on them,
    /// so an imperfect gap lands on the nearer of the two rather than failing.
    private static func classify(gap: Double, dit: Double) -> Element {
        if gap < dit * 2 { return .intraGap }
        if gap < dit * 5 { return .letterGap }
        return .wordGap
    }

    /// Two-means over one dimension, which is all the clustering this needs.
    ///
    /// Starting the centroids at the extremes makes it converge in a handful of
    /// passes, and a human's dit drifts across a sentence — so the split has to
    /// be found in the data rather than assumed from a nominal speed.
    static func split(_ values: [Double]) -> (short: [Double], long: [Double], ambiguous: Bool) {
        guard let low = values.min(), let high = values.max() else { return ([], [], true) }
        guard high / max(low, .leastNonzeroMagnitude) >= minimumContrast else {
            return (values, [], true)
        }

        var shortCentre = low
        var longCentre = high

        for _ in 0..<12 {
            let short = values.filter { abs($0 - shortCentre) <= abs($0 - longCentre) }
            let long = values.filter { abs($0 - shortCentre) > abs($0 - longCentre) }
            guard !short.isEmpty, !long.isEmpty else { break }

            let newShort = short.reduce(0, +) / Double(short.count)
            let newLong = long.reduce(0, +) / Double(long.count)
            if newShort == shortCentre && newLong == longCentre { break }
            shortCentre = newShort
            longCentre = newLong
        }

        return (values.filter { abs($0 - shortCentre) <= abs($0 - longCentre) },
                values.filter { abs($0 - shortCentre) > abs($0 - longCentre) },
                false)
    }
}

// MARK: - Scoring the fist

/// How well-formed the sending was, independent of whether it said the right
/// thing.
struct FistReport: Equatable, Sendable {

    let ditSeconds: Double
    /// Dah length over dit length. Should be 3.
    let dahRatio: Double?
    /// Letter gap over dit. Should be 3.
    let letterGapRatio: Double?
    /// Word gap over dit. Should be 7.
    let wordGapRatio: Double?
    /// Spread of the dits, as a fraction of their mean. Lower is steadier.
    let ditVariation: Double
    let dahVariation: Double
    /// Symbol groups that spelled nothing — letters run together far enough to
    /// merge into a code no character has.
    let unreadableGroups: Int

    var wpm: Double { ditSeconds > 0 ? Morse.Timing.wpm(ditTime: ditSeconds) : 0 }

    /// Plain-language faults, worst first. Empty when the fist is readable.
    ///
    /// This is the output that's worth having: "you sent GAT" you can hear for
    /// yourself, but "your dahs are twice your dits" you cannot.
    var notes: [String] {
        var notes: [String] = []

        if let dahRatio {
            if dahRatio < 2.4 { notes.append(String(format: "Dahs are %.1f× your dits — should be 3×", dahRatio)) }
            else if dahRatio > 3.8 { notes.append(String(format: "Dahs are %.1f× your dits — should be 3×", dahRatio)) }
        }
        if unreadableGroups > 0 {
            notes.append("Letters are running together — \(unreadableGroups) came out as one symbol, leave 3 dits between them")
        }
        if let letterGapRatio {
            if letterGapRatio < 2.2 { notes.append("Letters are running together — leave 3 dits between them") }
            else if letterGapRatio > 4.5 { notes.append("Long gaps between letters — 3 dits is the mark") }
        }
        if let wordGapRatio, wordGapRatio < 5.5 {
            notes.append("Words are running together — leave 7 dits between them")
        }
        if ditVariation > 0.25 { notes.append("Your dits wander — keep them even") }
        if dahVariation > 0.25 { notes.append("Your dahs wander — keep them even") }

        return notes
    }

    var isClean: Bool { notes.isEmpty }

    static func measure(_ presses: [Press]) -> FistReport? {
        guard presses.count > 1 else { return nil }

        let reading = FistDecoder.decode(presses)
        guard reading.ditSeconds > 0 else { return nil }

        let (shortGroup, longGroup, _) = FistDecoder.split(presses.map(\.duration))

        var intra: [Double] = [], letter: [Double] = [], word: [Double] = []
        for (previous, press) in zip(presses, presses.dropFirst()) {
            let gap = press.start - previous.end
            if gap < reading.ditSeconds * 2 { intra.append(gap) }
            else if gap < reading.ditSeconds * 5 { letter.append(gap) }
            else { word.append(gap) }
        }

        func mean(_ values: [Double]) -> Double? {
            values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        func variation(_ values: [Double]) -> Double {
            guard values.count > 1, let average = mean(values), average > 0 else { return 0 }
            let variance = values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(values.count)
            return variance.squareRoot() / average
        }

        return FistReport(
            ditSeconds: reading.ditSeconds,
            dahRatio: mean(longGroup).map { $0 / reading.ditSeconds },
            letterGapRatio: mean(letter).map { $0 / reading.ditSeconds },
            wordGapRatio: mean(word).map { $0 / reading.ditSeconds },
            ditVariation: variation(shortGroup),
            dahVariation: variation(longGroup),
            unreadableGroups: reading.unreadableGroups
        )
    }
}
