//
//  Pileup.swift
//  MorserX
//
//  Several stations calling at once — the thing that separates copying a code
//  from working a contest.
//
//  Real copy happens in a crowd: two or three signals overlapping, at different
//  pitches and different strengths, and you have to lock onto one and read it
//  through the others. A clean single tone never teaches that, and it's where
//  most operators fall down the first time they key up in a run.
//
//  The wanted signal is the strongest and its pitch is named, because that is how
//  you'd actually be told — "the loud one, up high." Copying whoever you can is a
//  later skill; this is the first rung.
//

import Foundation
import Morse

struct Pileup {

    /// One station in the crowd.
    struct Station: Equatable {
        let callsign: String
        let pitch: Float
        /// Loudness relative to the wanted signal.
        let gain: Float
        /// How far into the pileup this station starts calling, in seconds. Real
        /// callers don't all start together, and the stagger is half of what makes
        /// a pileup hard.
        let startSeconds: Double
        let isWanted: Bool
    }

    let stations: [Station]

    var wanted: Station { stations.first { $0.isWanted } ?? stations[0] }

    /// A plain-language cue for the signal to copy, since you're told which one.
    var cue: String {
        let others = stations.filter { !$0.isWanted }
        guard let quietest = others.map(\.pitch).min(),
              let loudest = others.map(\.pitch).max() else {
            return "Copy the call"
        }
        if wanted.pitch > loudest { return "Copy the strongest signal — the high one" }
        if wanted.pitch < quietest { return "Copy the strongest signal — the low one" }
        return "Copy the strongest signal"
    }

    /// Well-separated pitches, so two stations never sit on top of each other and
    /// become genuinely unreadable rather than merely crowded.
    static let pitches: [Float] = [480, 560, 640, 720, 800]

    /// Builds a pileup of `count` stations, one of them wanted.
    /// - Parameter makeCallsign: injected so a test can name the calls.
    static func make(count: Int,
                     context: DrillContext,
                     makeCallsign: (DrillContext) -> String) -> Pileup {
        let n = max(2, min(count, pitches.count))

        var pitchChoices = pitches
        // Pull `n` distinct pitches out, in the drill's own pseudo-random order.
        var chosenPitches: [Float] = []
        for _ in 0..<n {
            let index = min(context.randomIndex(pitchChoices.count), pitchChoices.count - 1)
            chosenPitches.append(pitchChoices.remove(at: index))
        }

        let wantedIndex = min(context.randomIndex(n), n - 1)

        let stations = (0..<n).map { i -> Station in
            let wanted = i == wantedIndex
            return Station(callsign: makeCallsign(context),
                           pitch: chosenPitches[i],
                           // The wanted signal is loudest; the rest sit under it,
                           // present but not competing for primacy.
                           gain: wanted ? 1.0 : 0.55,
                           // The wanted station starts first, so you can find it
                           // before the crowd piles in on top.
                           startSeconds: wanted ? 0 : Double(i + 1) * 0.15,
                           isWanted: wanted)
        }
        return Pileup(stations: stations)
    }
}
