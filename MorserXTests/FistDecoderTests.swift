//
//  FistDecoderTests.swift
//  MorserXTests
//
//  Reading morse back out of raw key timings.
//
//  This is the one piece of the app that has to work against input nobody
//  controls. A generated transmission is exact by construction; a human's
//  dit drifts, their dahs come out short under pressure, and their letter gaps
//  close up as they speed up. So the tests here are mostly deliberately sloppy
//  fists, built from timings rather than from symbols — because feeding it
//  perfect input would only prove the arithmetic, not the reading.
//

import Testing
import Foundation
import Morse
@testable import MorserX

// MARK: - Building a fist

/// Turns a morse string into presses at a given speed, so a test can describe
/// what was keyed rather than compute frame numbers by hand.
private func presses(sending morse: String,
                     dit: Double = 0.06,
                     dahRatio: Double = 3,
                     letterGapRatio: Double = 3,
                     wordGapRatio: Double = 7,
                     jitter: (Int) -> Double = { _ in 1 }) -> [Press] {
    var result: [Press] = []
    var clock = 0.0
    var index = 0
    var characters = Array(morse)
    var position = 0

    while position < characters.count {
        let character = characters[position]
        switch character {
        case ".", "-":
            let length = (character == "." ? dit : dit * dahRatio) * jitter(index)
            result.append(Press(start: clock, duration: length))
            clock += length + dit          // intra-character gap
            index += 1
            position += 1
        case " ":
            // Count the run of spaces: 3 is a letter gap, 7 a word gap.
            var spaces = 0
            while position < characters.count && characters[position] == " " {
                spaces += 1
                position += 1
            }
            // The intra gap was already added after the previous element.
            let ratio = spaces >= 7 ? wordGapRatio : letterGapRatio
            clock += dit * (ratio - 1)
        default:
            position += 1
        }
    }
    return result
}

// MARK: - Recording

struct FistRecorderTests {

    @Test("a press is recorded from down to up")
    func recordsPresses() {
        var recorder = FistRecorder()
        recorder.down(at: 100.0)
        recorder.up(at: 100.06)
        recorder.down(at: 100.12)
        recorder.up(at: 100.30)

        #expect(recorder.presses.count == 2)
        // Times are relative to the first key-down, so the record doesn't depend
        // on when the session happened to start.
        #expect(recorder.presses[0].start == 0)
        #expect(abs(recorder.presses[0].duration - 0.06) < 1e-9)
        #expect(abs(recorder.presses[1].start - 0.12) < 1e-9)
    }

    @Test("a key already down isn't re-triggered by a repeat")
    func ignoresRepeatedDown() {
        var recorder = FistRecorder()
        recorder.down(at: 1)
        recorder.down(at: 1.01)
        recorder.up(at: 1.06)

        #expect(recorder.presses.count == 1)
        #expect(abs(recorder.presses[0].duration - 0.06) < 1e-9)
    }

    @Test("an up with no down is not a press")
    func ignoresStrayUp() {
        var recorder = FistRecorder()
        recorder.up(at: 5)
        #expect(recorder.presses.isEmpty)
    }

    @Test("resetting clears the timebase as well as the presses")
    func reset() {
        var recorder = FistRecorder()
        recorder.down(at: 10); recorder.up(at: 10.1)
        recorder.reset()
        recorder.down(at: 99); recorder.up(at: 99.06)

        #expect(recorder.presses.count == 1)
        #expect(recorder.presses[0].start == 0)
    }
}

// MARK: - Decoding

struct FistDecoderTests {

    @Test("a clean fist reads back as what was sent")
    func perfectFist() {
        let reading = FistDecoder.decode(presses(sending: Morse.morse(from: "cq")))

        #expect(reading.text == "CQ")
        #expect(!reading.isAmbiguous)
    }

    @Test("word gaps come back as word gaps")
    func words() {
        let reading = FistDecoder.decode(presses(sending: Morse.morse(from: "cq de")))
        #expect(reading.text == "CQ DE")
    }

    @Test("the dit is estimated from the sending, not assumed from a nominal speed")
    func estimatesDit() {
        for dit in [0.04, 0.06, 0.1, 0.15] {
            let reading = FistDecoder.decode(presses(sending: Morse.morse(from: "test"), dit: dit))
            #expect(abs(reading.ditSeconds - dit) < dit * 0.15,
                    "estimated \(reading.ditSeconds) for a \(dit) dit")
            #expect(reading.text == "TEST")
        }
    }

    /// A human's dit wanders. If a wandering dit broke the reading, the decoder
    /// would only ever work on input the app generated itself.
    @Test("a wobbly fist still reads")
    func toleratesJitter() {
        let wobble: [Double] = [1.12, 0.9, 1.05, 0.93, 1.15, 0.88, 1.0, 1.08, 0.95, 1.1, 0.92, 1.06]
        let reading = FistDecoder.decode(
            presses(sending: Morse.morse(from: "hello"), jitter: { wobble[$0 % wobble.count] })
        )

        #expect(reading.text == "HELLO")
    }

    /// Short dahs are the classic beginner fault — and the one you can't hear
    /// yourself, because to you they still sound like dahs.
    @Test("dahs at only 2.2x still read as dahs")
    func tolerantOfShortDahs() {
        let reading = FistDecoder.decode(presses(sending: Morse.morse(from: "cq"), dahRatio: 2.2))
        #expect(reading.text == "CQ")
    }

    @Test("gaps that are a little tight still separate the letters")
    func tolerantOfTightGaps() {
        let reading = FistDecoder.decode(
            presses(sending: Morse.morse(from: "sos"), letterGapRatio: 2.4)
        )
        #expect(reading.text == "SOS")
    }

    /// With no contrast there is genuinely nothing to read: a run of identical
    /// presses is the same whether every one was meant as a dit or as a dah.
    /// Guessing silently would be worse than saying so.
    @Test("a fist with no contrast is reported as ambiguous rather than guessed at")
    func ambiguousFist() {
        let flat = (0..<5).map { Press(start: Double($0) * 0.12, duration: 0.06) }
        let reading = FistDecoder.decode(flat)

        #expect(reading.isAmbiguous)
        #expect(reading.morse == ".....")
    }

    @Test("nothing keyed decodes to nothing")
    func empty() {
        #expect(FistDecoder.decode([]) == .empty)
    }

    @Test("one press is read, not dropped")
    func singlePress() {
        let reading = FistDecoder.decode([Press(start: 0, duration: 0.06)])
        #expect(reading.morse == ".")
        #expect(reading.isAmbiguous)
    }

    @Test("the split finds the two groups rather than the extremes")
    func clustering() {
        let (short, long, ambiguous) = FistDecoder.split([0.05, 0.06, 0.055, 0.18, 0.19, 0.17])

        #expect(!ambiguous)
        #expect(short.count == 3)
        #expect(long.count == 3)
    }
}

// MARK: - Scoring the fist

struct FistReportTests {

    @Test("a clean fist has nothing to say about it")
    func cleanFist() {
        let report = FistReport.measure(presses(sending: Morse.morse(from: "cq de")))

        #expect(report != nil)
        #expect(report?.isClean == true, "complained about a perfect fist: \(report?.notes ?? [])")
        #expect(abs((report?.dahRatio ?? 0) - 3) < 0.2)
        #expect(abs((report?.letterGapRatio ?? 0) - 3) < 0.3)
    }

    /// The whole point of the mode: this is the fault you cannot hear yourself.
    @Test("short dahs are named, with the number")
    func catchesShortDahs() {
        let report = FistReport.measure(presses(sending: Morse.morse(from: "cq de"), dahRatio: 2.0))

        #expect(report?.isClean == false)
        #expect(report?.notes.contains(where: { $0.contains("Dahs are") }) == true)
        #expect(abs((report?.dahRatio ?? 0) - 2.0) < 0.25)
    }

    @Test("letters run together is named")
    func catchesTightLetterGaps() {
        let report = FistReport.measure(
            presses(sending: Morse.morse(from: "sos"), letterGapRatio: 1.6)
        )
        #expect(report?.notes.contains(where: { $0.contains("running together") }) == true)
    }

    @Test("an uneven fist is named even when every symbol is readable")
    func catchesWander() {
        let wild: [Double] = [1.6, 0.5, 1.5, 0.55, 1.55, 0.5, 1.45, 0.6]
        let report = FistReport.measure(
            presses(sending: Morse.morse(from: "hello"), jitter: { wild[$0 % wild.count] })
        )

        #expect(report?.notes.contains(where: { $0.contains("wander") }) == true)
    }

    @Test("speed is reported in the units an operator thinks in")
    func reportsWPM() {
        let report = FistReport.measure(presses(sending: Morse.morse(from: "test"), dit: 0.06))

        // 1.2 / 0.06 = 20 wpm.
        #expect(abs((report?.wpm ?? 0) - 20) < 1.5)
    }

    @Test("one press isn't enough to judge a fist on")
    func tooLittleToJudge() {
        #expect(FistReport.measure([Press(start: 0, duration: 0.06)]) == nil)
        #expect(FistReport.measure([]) == nil)
    }
}

// MARK: - Sending drill

@MainActor
struct SendingDrillTests {

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

    /// Nothing is played, so waiting for the audio to finish would leave the
    /// round stuck before it started.
    @Test("a keyed round is ready to answer the moment it starts")
    func startsAnswering() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .sending
        session.startRound()

        #expect(session.phase == .answering)
        #expect(!session.prompt.isEmpty)
        #expect(session.answerMethod == .keyed)
    }

    @Test("the prompt is two words, so a word gap is part of the exercise")
    func twoWords() {
        let prompt = SendingDrill().makePrompt(DrillContext())
        #expect(prompt.split(separator: " ").count == 2)
    }

    @Test("keying the prompt correctly marks it correct")
    func keyingItRightScoresRight() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .sending
        session.startRound()

        let keyed = pressesFor(text: session.prompt)
        session.submitKeyed(presses: keyed)

        #expect(session.answer == session.prompt.uppercased())
        #expect(session.grade?.accuracy == 1.0)
        #expect(session.fistReport?.isClean == true)
    }

    /// The point of the mode: the text can be perfect while the fist is not.
    @Test("a readable-but-badly-formed fist is marked right on text and wrong on timing")
    func textRightFistWrong() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .sending
        session.startRound()

        let keyed = pressesFor(text: session.prompt, dahRatio: 2.0)
        session.submitKeyed(presses: keyed)

        #expect(session.grade?.accuracy == 1.0, "the text should still read")
        #expect(session.fistReport?.isClean == false, "but the fist should be faulted")
        #expect(session.fistReport?.notes.contains(where: { $0.contains("Dahs are") }) == true)
    }

    /// Builds presses for arbitrary text at a chosen dah ratio.
    private func pressesFor(text: String, dit: Double = 0.06, dahRatio: Double = 3) -> [Press] {
        var result: [Press] = []
        var clock = 0.0

        for (wordIndex, word) in text.uppercased().split(separator: " ").enumerated() {
            if wordIndex > 0 { clock += dit * 6 }        // word gap: 7 dits, less the 1 already added
            for (characterIndex, character) in word.enumerated() {
                if characterIndex > 0 { clock += dit * 2 }   // letter gap: 3 dits, less the 1 already added
                guard let code = Morse.code(for: character) else { continue }
                for symbol in code {
                    let length = symbol == "." ? dit : dit * dahRatio
                    result.append(Press(start: clock, duration: length))
                    clock += length + dit
                }
            }
        }
        return result
    }
}
