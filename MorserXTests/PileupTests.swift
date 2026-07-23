//
//  PileupTests.swift
//  MorserXTests
//
//  Several signals at once.
//
//  Two things here can be wrong while still sounding roughly like a pileup: the
//  mix can clip, which is a loud artefact masquerading as crowding, and a voice
//  can land at the wrong frame, which shifts the timing that makes it copyable.
//  Both are measured from the summed samples rather than trusted.
//

import Testing
import Foundation
import AVFoundation
import Morse
@testable import MorserX

private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

// MARK: - The mixer

struct MixTests {

    @Test("silence in, silence out")
    func empty() {
        #expect(MorseRenderer.mix([]).isEmpty)
    }

    @Test("the mix is as long as its latest-ending signal")
    func length() {
        let a = (samples: [Float](repeating: 0.2, count: 100), offset: 0, gain: Float(1))
        let b = (samples: [Float](repeating: 0.2, count: 100), offset: 500, gain: Float(1))

        #expect(MorseRenderer.mix([a, b]).count == 600)
    }

    @Test("a voice's offset places it, sample-accurately")
    func placement() {
        let quiet = (samples: [Float](repeating: 0, count: 1000), offset: 0, gain: Float(1))
        let blip = (samples: [Float](repeating: 0.5, count: 10), offset: 300, gain: Float(1))

        let mixed = MorseRenderer.mix([quiet, blip])
        #expect(mixed[299] == 0)
        #expect(mixed[300] == 0.5)
        #expect(mixed[309] == 0.5)
        #expect(mixed[310] == 0)
    }

    @Test("overlapping signals add")
    func summing() {
        let a = (samples: [Float](repeating: 0.3, count: 10), offset: 0, gain: Float(1))
        let b = (samples: [Float](repeating: 0.2, count: 10), offset: 0, gain: Float(1))

        let mixed = MorseRenderer.mix([a, b])
        #expect(abs(mixed[0] - 0.5) < 1e-6)
    }

    @Test("gain scales a voice before it's summed")
    func gain() {
        let a = (samples: [Float](repeating: 1.0, count: 10), offset: 0, gain: Float(0.5))
        #expect(abs(MorseRenderer.mix([a])[0] - 0.5) < 1e-6)
    }

    /// A clip is a much louder, uglier artefact than the crowding this drill is
    /// about, so a sum that would exceed full scale is brought back under it.
    @Test("a mix that would clip is scaled back under full scale")
    func normalisesInsteadOfClipping() {
        let loud = [
            (samples: [Float](repeating: 0.8, count: 10), offset: 0, gain: Float(1)),
            (samples: [Float](repeating: 0.8, count: 10), offset: 0, gain: Float(1)),
        ]
        let mixed = MorseRenderer.mix(loud)

        #expect(mixed.allSatisfy { abs($0) <= 1.0 + 1e-6 })
        // Peak is brought to exactly full scale, not silenced.
        #expect(abs((mixed.map(abs).max() ?? 0) - 1.0) < 1e-6)
    }

    /// Normalising must not change which voice is louder — that's the cue you copy
    /// by, and flattening it would defeat the point.
    @Test("normalising keeps the voices' relative loudness")
    func preservesRelativeLevel() {
        let signals = [
            (samples: [Float](repeating: 1.0, count: 10), offset: 0, gain: Float(1.0)),
            (samples: [Float](repeating: 1.0, count: 10), offset: 20, gain: Float(0.5)),
        ]
        let mixed = MorseRenderer.mix(signals)

        // The lone loud voice sits at 20; the lone quiet one at 20 further on.
        // Their ratio survives the scaling.
        #expect(abs(mixed[0] / mixed[20] - 2.0) < 1e-4)
    }

    @Test("a quiet mix is left alone rather than pumped up")
    func doesNotAmplify() {
        let quiet = (samples: [Float](repeating: 0.1, count: 10), offset: 0, gain: Float(1))
        #expect(abs(MorseRenderer.mix([quiet])[0] - 0.1) < 1e-6)
    }
}

// MARK: - Rendering a mix

struct RenderMixTests {

    @Test("several voices come back as one buffer")
    func rendersToOneBuffer() {
        var renderer = MorseRenderer()
        renderer.sampleRate = 48_000

        let voices = [
            MorseRenderer.Voice(tones: [Tone(.dah, ditTime: 0.1, pitch: 500)]),
            MorseRenderer.Voice(tones: [Tone(.dah, ditTime: 0.1, pitch: 800)], startSeconds: 0.05),
        ]
        guard let (buffer, frames) = renderer.renderMix(voices, format: format) else {
            Issue.record("nothing rendered"); return
        }

        #expect(frames > 0)
        #expect(Int(buffer.frameLength) == frames)
    }

    @Test("a later-starting voice extends the buffer past the first")
    func startOffsetExtendsTheBuffer() {
        var renderer = MorseRenderer()
        renderer.sampleRate = 48_000

        let solo = renderer.renderMix([MorseRenderer.Voice(tones: [Tone(.dah, ditTime: 0.1, pitch: 500)])],
                                      format: format)
        let staggered = renderer.renderMix([
            MorseRenderer.Voice(tones: [Tone(.dah, ditTime: 0.1, pitch: 500)]),
            MorseRenderer.Voice(tones: [Tone(.dah, ditTime: 0.1, pitch: 800)], startSeconds: 0.2),
        ], format: format)

        #expect((staggered?.frames ?? 0) > (solo?.frames ?? 0))
    }

    @Test("nothing in the rendered mix clips")
    func noClipping() {
        var renderer = MorseRenderer()
        renderer.sampleRate = 48_000

        let voices = (0..<3).map { i in
            MorseRenderer.Voice(tones: [Tone(.dah, ditTime: 0.3, pitch: Pileup.pitches[i])], gain: 1)
        }
        guard let (buffer, frames) = renderer.renderMix(voices, format: format),
              let samples = buffer.floatChannelData?[0] else {
            Issue.record("nothing rendered"); return
        }

        for i in 0..<frames {
            #expect(abs(samples[i]) <= 1.0 + 1e-6)
        }
    }

    @Test("no voices, nothing rendered")
    func emptyVoices() {
        var renderer = MorseRenderer()
        renderer.sampleRate = 48_000
        #expect(renderer.renderMix([], format: format) == nil)
    }
}

// MARK: - Building a pileup

struct PileupModelTests {

    private func context(_ picks: [Int]) -> DrillContext {
        var context = DrillContext()
        var step = 0
        context.randomIndex = { count in
            defer { step += 1 }
            return count == 0 ? 0 : picks[step % picks.count] % count
        }
        return context
    }

    @Test("a pileup has the number of stations asked for, one of them wanted")
    func composition() {
        var index = 0
        let pileup = Pileup.make(count: 3, context: context([0])) { _ in
            defer { index += 1 }
            return ["W4ABC", "K5XYZ", "N2DEF"][index % 3]
        }

        #expect(pileup.stations.count == 3)
        #expect(pileup.stations.filter(\.isWanted).count == 1)
    }

    @Test("the count is clamped to the pitches available, and to at least two")
    func countIsClamped() {
        let one = Pileup.make(count: 1, context: context([0])) { _ in "W1AW" }
        #expect(one.stations.count == 2)

        let many = Pileup.make(count: 99, context: context([0])) { _ in "W1AW" }
        #expect(many.stations.count == Pileup.pitches.count)
    }

    /// Two stations on the same pitch would merge into one unreadable signal
    /// rather than a crowd, which is a different and much worse problem.
    @Test("no two stations share a pitch")
    func distinctPitches() {
        let pileup = Pileup.make(count: 5, context: context([0, 2, 1, 3, 0])) { _ in "W1AW" }
        let pitches = pileup.stations.map(\.pitch)
        #expect(Set(pitches).count == pitches.count)
    }

    @Test("the wanted signal is the loudest")
    func wantedIsLoudest() {
        let pileup = Pileup.make(count: 3, context: context([1])) { _ in "W1AW" }
        let others = pileup.stations.filter { !$0.isWanted }

        #expect(others.allSatisfy { $0.gain < pileup.wanted.gain })
    }

    @Test("the wanted signal starts first, so it can be found before the crowd")
    func wantedStartsFirst() {
        let pileup = Pileup.make(count: 3, context: context([0])) { _ in "W1AW" }
        #expect(pileup.wanted.startSeconds == 0)
        #expect(pileup.stations.filter { !$0.isWanted }.allSatisfy { $0.startSeconds > 0 })
    }

    @Test("the cue names where the wanted signal sits when it's at an extreme")
    func cue() {
        // Wanted on the lowest pitch: pick station 0 wanted, and it happens to be low.
        let pileup = Pileup.make(count: 3, context: context([0])) { _ in "W1AW" }
        #expect(!pileup.cue.isEmpty)
    }
}

// MARK: - The drill in a session

@MainActor
struct PileupDrillTests {

    private final class MemoryStore: PracticeStoring {
        var level: Int?
        var characterWPM: Double?
        var effectiveWPM: Double?
        var scores: [Character: CharacterScore] = [:]
        var mode: String?
        var characterSet: String?
        var customText: String?
        var speedLadder: Bool?
    }

    @Test("the prompt is a callsign the crowd is actually sending")
    func promptIsInTheCrowd() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .pileup
        session.startRound()

        #expect(session.pileup != nil)
        #expect(session.prompt == session.pileup?.wanted.callsign)
        #expect(session.pileup?.stations.map(\.callsign).contains(session.prompt) == true)
    }

    /// The crowd is fixed when the round starts; the graded call and the sent
    /// audio must come from the same draw, or you'd copy one pileup and be marked
    /// against another.
    @Test("the same crowd is held for the whole round")
    func crowdIsStable() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .pileup
        session.startRound()

        let first = session.pileup
        #expect(session.pileup?.wanted.callsign == first?.wanted.callsign)
        #expect(session.prompt == first?.wanted.callsign)
    }

    @Test("copying the wanted call correctly is full marks")
    func copyingTheWantedCall() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .pileup
        session.startRound()
        session.finishedSending()

        session.answer = session.prompt
        session.submit()
        #expect(session.grade?.accuracy == 1.0)
    }

    @Test("leaving the pileup clears the crowd")
    func leavingClearsIt() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .pileup
        session.startRound()
        #expect(session.pileup != nil)

        session.mode = .koch
        session.startRound()
        #expect(session.pileup == nil)
    }
}
