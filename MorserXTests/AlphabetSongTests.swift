//
//  AlphabetSongTests.swift
//  MorserXTests
//
//  Per-element pitch, and the song that needed it.
//
//  The renderer used to compute one phase step for the whole transmission while
//  every Tone carried a `frequency` nobody read — so "supports per-tone pitch"
//  was true of the data model and false of the sound. These measure the samples
//  that actually come out, because that was exactly the gap.
//

import Testing
import Foundation
import AVFoundation
import Morse
@testable import MorserX

// MARK: - Measuring what came out

/// Estimates a span's pitch by counting zero crossings through its steady middle,
/// away from the envelope ramps at either edge.
private func measuredPitch(_ buffer: AVAudioPCMBuffer, span: ToneSpan, sampleRate: Double) -> Double {
    guard let samples = buffer.floatChannelData?[0], span.frameCount > 200 else { return 0 }

    let inset = span.frameCount / 4
    let start = span.startFrame + inset
    let count = span.frameCount - inset * 2
    guard count > 1 else { return 0 }

    var crossings = 0
    for i in 1..<count {
        let previous = samples[start + i - 1]
        let current = samples[start + i]
        if (previous < 0) != (current < 0) { crossings += 1 }
    }

    let seconds = Double(count) / sampleRate
    return Double(crossings) / 2 / seconds
}

private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!

// MARK: - Renderer

struct PitchedRenderingTests {

    @Test("a tone with no pitch of its own is sounded at the sidetone")
    func defaultsToSidetone() {
        var renderer = MorseRenderer()
        renderer.sampleRate = 48_000

        let tones = [Tone(.dah, ditTime: 0.2)]
        guard let (buffer, spans) = renderer.render(tones, format: format) else {
            Issue.record("nothing rendered"); return
        }

        #expect(abs(measuredPitch(buffer, span: spans[0], sampleRate: 48_000) - renderer.frequency) < 15)
    }

    /// The claim the old code quietly failed: this is measured from the samples,
    /// not from the field that was set.
    @Test("a tone's own pitch is what actually comes out")
    func honoursPitch() {
        var renderer = MorseRenderer()
        renderer.sampleRate = 48_000

        for wanted: Float in [523.25, 659.25, 880] {
            let tones = [Tone(.dah, ditTime: 0.2, pitch: wanted)]
            guard let (buffer, spans) = renderer.render(tones, format: format) else {
                Issue.record("nothing rendered"); return
            }

            let measured = measuredPitch(buffer, span: spans[0], sampleRate: 48_000)
            #expect(abs(measured - Double(wanted)) < 15,
                    "asked for \(wanted)Hz, measured \(measured)Hz")
        }
    }

    @Test("elements in one transmission can differ in pitch")
    func pitchVariesWithinATransmission() {
        var renderer = MorseRenderer()
        renderer.sampleRate = 48_000

        let tones = [
            Tone(.dah, ditTime: 0.2, pitch: 523.25),
            Tone(.letterSpace, ditTime: 0.2),
            Tone(.dah, ditTime: 0.2, pitch: 880)
        ]
        guard let (buffer, spans) = renderer.render(tones, format: format) else {
            Issue.record("nothing rendered"); return
        }

        let first = measuredPitch(buffer, span: spans[0], sampleRate: 48_000)
        let last = measuredPitch(buffer, span: spans[2], sampleRate: 48_000)

        #expect(abs(first - 523.25) < 15)
        #expect(abs(last - 880) < 15)
    }

    /// Changing pitch must not change the timing: the frame layout is what makes
    /// morse legible, and it has nothing to do with the note.
    @Test("pitch doesn't disturb the frame layout")
    func timingIsUnchanged() {
        var renderer = MorseRenderer()
        renderer.sampleRate = 48_000

        let plain = [Tone(.dit, ditTime: 0.1), Tone(.infraSpace, ditTime: 0.1), Tone(.dah, ditTime: 0.1)]
        let sung = [Tone(.dit, ditTime: 0.1, pitch: 880),
                    Tone(.infraSpace, ditTime: 0.1),
                    Tone(.dah, ditTime: 0.1, pitch: 523.25)]

        #expect(renderer.spans(for: plain) == renderer.spans(for: sung))
    }

    /// Every sample stays inside the envelope's bound, so a pitch change can't
    /// produce a step that reads as a click.
    @Test("nothing exceeds full scale at a pitch change")
    func noDiscontinuity() {
        var renderer = MorseRenderer()
        renderer.sampleRate = 48_000

        let tones = [Tone(.dah, ditTime: 0.15, pitch: 523.25), Tone(.dah, ditTime: 0.15, pitch: 880)]
        guard let (buffer, _) = renderer.render(tones, format: format),
              let samples = buffer.floatChannelData?[0] else {
            Issue.record("nothing rendered"); return
        }

        var largestStep: Float = 0
        for i in 1..<Int(buffer.frameLength) {
            largestStep = max(largestStep, abs(samples[i] - samples[i - 1]))
        }
        // One sample of an 880Hz sine at 48kHz moves ~0.115 of full scale; the
        // amplitude is 0.35, so anything past ~0.05 would be a jump, not a slope.
        #expect(largestStep < 0.06, "largest sample step was \(largestStep)")
    }
}

// MARK: - The song

struct AlphabetSongTests {

    @Test("every letter has a note")
    func coversTheAlphabet() {
        for letter in Morse.Alphabet.letters.characters {
            #expect(AlphabetSong.notes[letter] != nil, "\(letter) has no note")
        }
        #expect(AlphabetSong.notes.count == 26)
    }

    @Test("the phrasing is the alphabet, in order, in the song's breaths")
    func phrasing() {
        let joined = AlphabetSong.phrases.joined()
        #expect(joined == "abcdefghijklmnopqrstuvwxyz")
        #expect(AlphabetSong.phrases.count == 6)
    }

    @Test("the whole song is sendable")
    func sendable() {
        let encoded = Morse.encode(AlphabetSong.text)
        #expect(encoded.isComplete)
        #expect(encoded.tokens.count == 26)
    }

    @Test("pitches sit in the range a sidetone lives in")
    func pitchRange() {
        for note in AlphabetSong.Note.allCases {
            #expect(note.rawValue > 400 && note.rawValue < 1000)
        }
    }

    /// The crutch has to be removable, or it's just a worse way to practise.
    @Test("fading takes the melody away")
    func fade() {
        let sung = AlphabetSong.pitch(for: "A", fade: 0)
        #expect(sung == AlphabetSong.Note.C.rawValue)

        // Fully faded: no pitch of its own, so the sidetone is used.
        #expect(AlphabetSong.pitch(for: "A", fade: 1) == nil)

        // Halfway: between the note and the sidetone, not one or the other.
        // A sits on C, which is *below* the 600Hz sidetone, so fading raises it.
        let half = AlphabetSong.pitch(for: "A", fade: 0.5)
        #expect(half != nil)
        #expect(half! > sung!)
        #expect(half! < 600)
    }

    @Test("characters outside the alphabet aren't given a note")
    func nonLetters() {
        #expect(AlphabetSong.pitch(for: "5") == nil)
        #expect(AlphabetSong.pitch(for: " ") == nil)
    }

    @Test("lowercase is the same letter")
    func caseInsensitive() {
        #expect(AlphabetSong.pitch(for: "a") == AlphabetSong.pitch(for: "A"))
    }
}

// MARK: - Building the tones

struct PitchedTonesTests {

    @Test("each character's symbols carry that character's pitch")
    func pitchPerCharacter() async {
        let conductor = Conductor()
        let tones = await conductor.pitchedTones(for: "ab", ditTime: 0.1) { character in
            character == "A" ? 500 : 900
        }

        let sounded = tones.filter { $0.amplitude > 0 }
        // A is .- and B is -... — two symbols then four.
        #expect(sounded.count == 6)
        #expect(sounded.prefix(2).allSatisfy { $0.pitch == 500 })
        #expect(sounded.dropFirst(2).allSatisfy { $0.pitch == 900 })
    }

    @Test("the spacing is the same as any other transmission")
    func spacing() async {
        let conductor = Conductor()
        let tones = await conductor.pitchedTones(for: "ee ee", ditTime: 0.1) { _ in nil }

        // E is one dit. Two letters, a word gap, two letters:
        // dit, letterGap, dit, wordGap, dit, letterGap, dit
        #expect(tones.count == 7)
        #expect(abs(tones[1].duration - 0.3) < 1e-9)   // letter gap, 3 dits
        #expect(abs(tones[3].duration - 0.7) < 1e-9)   // word gap, 7 dits
    }

    @Test("Farnsworth spacing still applies to a sung transmission")
    func farnsworth() async {
        let conductor = Conductor()
        let tones = await conductor.pitchedTones(for: "ee", ditTime: 0.06, spaceDitTime: 0.2) { _ in nil }

        #expect(tones[0].duration == 0.06)
        #expect(abs(tones[1].duration - 0.6) < 1e-9)   // 3 × the wider spacing dit
    }

    @Test("unsendable characters are skipped rather than sounded as silence")
    func skipsUnsendable() async {
        let conductor = Conductor()
        let tones = await conductor.pitchedTones(for: "a#a", ditTime: 0.1) { _ in nil }

        #expect(tones.filter { $0.amplitude > 0 }.count == 4)   // two A's, two symbols each
    }
}

// MARK: - The drill

@MainActor
struct AlphabetSongDrillTests {

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

    @Test("the song is listened to, not answered")
    func listenOnly() {
        #expect(AlphabetSongDrill().answerMethod == .listenOnly)
        #expect(AlphabetSongDrill().makePrompt(DrillContext()) == AlphabetSong.text)
    }

    /// A round with nothing to answer has to end when the audio does, or the
    /// session sits in `.answering` waiting for something that never comes.
    @Test("the round ends when the sending does")
    func roundEndsWithTheAudio() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .song
        session.startRound()
        #expect(session.phase == .sending)

        session.finishedSending()
        #expect(session.phase == .ready)
        #expect(session.grade == nil)
    }

    @Test("only the song is sung — every other drill stays on the sidetone")
    func pitchOnlyForTheSong() {
        let session = PracticeSession(store: MemoryStore())

        session.mode = .song
        #expect(session.pitch(for: "A") != nil)

        session.mode = .koch
        #expect(session.pitch(for: "A") == nil)
    }
}
