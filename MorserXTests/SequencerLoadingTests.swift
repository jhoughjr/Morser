//
//  SequencerLoadingTests.swift
//  MorserXTests
//
//  Pins the text → morse → sequencer chain, which used to have two holes in it:
//  the launch text was never encoded (the TextField's onChange was the only thing
//  that called the encoder), and the sequencer was filled only by `sound()`, so it
//  stayed empty until Play regardless of what was typed.
//

import Testing
import Morse
@testable import MorserX

@MainActor
struct SequencerLoadingTests {

    @Test("the launch text is already encoded, before anything is typed")
    func encodesOnInit() {
        let controller = Controllers.MorseController()

        #expect(!controller.morseText.isEmpty)
        #expect(controller.morseCode == Morse.morse(from: controller.morseText))
        #expect(!controller.morseCode.isEmpty)
    }

    @Test("editing the text re-encodes it without a view driving the conversion")
    func encodesOnEdit() {
        let controller = Controllers.MorseController()

        controller.morseText = "sos"

        #expect(controller.morseCode == "...   ---   ...")
    }

    @Test("clearing the text clears the code rather than leaving the last one")
    func clearingEmptiesCode() {
        let controller = Controllers.MorseController()

        controller.morseText = ""

        #expect(controller.morseCode.isEmpty)
    }

    @Test("loading fills the sequencer without starting playback")
    func loadPublishesTonesWithoutPlaying() async {
        let conductor = Conductor()

        await conductor.load(morse: Morse.morse(from: "sos"), with: 0.05)
        await settle()

        #expect(!conductor.tones.isEmpty)
        #expect(conductor.isPlaying == false)
        #expect(conductor.currentTone == nil)
        // s o s — six sounded symbols, so the strip has at least that many cells.
        #expect(conductor.tones.filter { $0.tone.amplitude > 0 }.count == 9)
    }

    @Test("a second load replaces the sequence instead of appending to it")
    func loadReplaces() async {
        let conductor = Conductor()

        await conductor.load(morse: Morse.morse(from: "sos"), with: 0.05)
        await settle()
        let first = conductor.tones.count

        await conductor.load(morse: Morse.morse(from: "e"), with: 0.05)
        await settle()

        #expect(conductor.tones.count < first)
        #expect(conductor.tones.count == 1)
    }

    @Test("empty text yields an empty sequence, not a stale one")
    func loadEmpty() async {
        let conductor = Conductor()

        await conductor.load(morse: Morse.morse(from: "sos"), with: 0.05)
        await settle()
        await conductor.load(morse: "", with: 0.05)
        await settle()

        #expect(conductor.tones.isEmpty)
    }

    /// `load` publishes onto the MainActor from inside the actor, so the write
    /// lands a hop later than the call returns.
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(120))
    }
}
