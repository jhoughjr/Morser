//
//  PracticeDrillTests.swift
//  MorserXTests
//
//  A drill is only two claims: which characters are in play, and how they're
//  arranged. Both are easy to get subtly wrong in ways that still look like a
//  plausible prompt on screen — a callsign with no digit, a set filter that
//  quietly falls back to letters, a custom drill that always sends the same
//  window of the same text.
//

import Testing
import Foundation
import Morse
@testable import MorserX

/// Picks deterministically, so "random" is an argument rather than something to
/// work around. `.zero` always takes the first option; `.cycling` walks them.
private enum Picker {
    static var zero: (Int) -> Int { { _ in 0 } }

    static func cycling() -> (Int) -> Int {
        var step = 0
        return { count in
            defer { step += 1 }
            return count == 0 ? 0 : step % count
        }
    }
}

private func context(_ mutate: (inout DrillContext) -> Void = { _ in }) -> DrillContext {
    var context = DrillContext()
    context.randomIndex = Picker.cycling()
    // The custom drill has nothing to send without this, and a shared helper
    // that yields an empty prompt would look like a drill bug rather than a
    // missing argument.
    context.customText = "cq de w4abc pse k"
    mutate(&context)
    return context
}

// MARK: - Every drill

struct EveryDrillTests {

    @Test("every mode produces something sendable", arguments: PracticeMode.allCases)
    func promptsAreSendable(mode: PracticeMode) {
        let prompt = mode.drill.makePrompt(context())

        #expect(!prompt.isEmpty, "\(mode) produced no prompt")
        let encoded = Morse.encode(prompt)
        #expect(encoded.isComplete, "\(mode) produced \(encoded.skipped) which can't be sent")
        #expect(!encoded.morse.isEmpty)
    }

    @Test("only Koch walks a ladder", arguments: PracticeMode.allCases)
    func levelsBelongToKoch(mode: PracticeMode) {
        #expect(mode.drill.usesLevels == (mode == .koch))
    }

    @Test("a prompt is made of groups, never one run-on string", arguments: PracticeMode.allCases)
    func promptsAreGrouped(mode: PracticeMode) {
        let prompt = mode.drill.makePrompt(context { $0.groupCount = 4 })

        #expect(!prompt.hasPrefix(" "))
        #expect(!prompt.hasSuffix(" "))
        #expect(!prompt.contains("  "))
    }
}

// MARK: - Koch

struct KochDrillTests {

    @Test("a prompt only contains characters that are in play")
    func staysInAlphabet() {
        let drill = KochDrill()
        var ctx = context { $0.level = 6 }

        for _ in 0..<20 {
            ctx.randomIndex = Picker.cycling()
            let prompt = drill.makePrompt(ctx)
            let used = Set(prompt.filter { !$0.isWhitespace })
            #expect(used.isSubset(of: Set(drill.alphabet(ctx))))
        }
    }

    @Test("the prompt is laid out as the requested number of groups")
    func shape() {
        let prompt = KochDrill().makePrompt(context {
            $0.randomIndex = Picker.zero
            $0.groupCount = 4
            $0.groupSize = 5
        })

        let groups = prompt.split(separator: " ")
        #expect(groups.count == 4)
        let allFive = groups.allSatisfy { $0.count == 5 }
        #expect(allFive)
    }
}

// MARK: - Character set

struct CharacterSetDrillTests {

    @Test("each set draws only from itself",
          arguments: [CharacterSetChoice.letters, .digits, .punctuation, .alphanumeric])
    func drawsFromTheChosenSet(choice: CharacterSetChoice) {
        let drill = CharacterSetDrill()
        let ctx = context { $0.characterSet = choice }

        let used = Set(drill.makePrompt(ctx).filter { !$0.isWhitespace })
        #expect(used.isSubset(of: Set(choice.characters(scores: [:]))))
        #expect(!used.isEmpty)
    }

    @Test("numbers means numbers")
    func digitsOnly() {
        let prompt = CharacterSetDrill().makePrompt(context { $0.characterSet = .digits })
        let allDigits = prompt.filter { !$0.isWhitespace }.allSatisfy { $0.isNumber }
        #expect(allDigits)
    }

    @Test("'my worst' drills what you've been missing, worst first")
    func weakestUsesTheRecord() {
        let scores: [Character: CharacterScore] = [
            "Q": CharacterScore(attempts: 10, hits: 1),
            "Z": CharacterScore(attempts: 10, hits: 3),
            "E": CharacterScore(attempts: 10, hits: 10)
        ]
        let characters = CharacterSetChoice.weakest.characters(scores: scores)

        #expect(characters.first == "Q")
        #expect(characters == ["Q", "Z", "E"])
    }

    /// With nothing heard yet there is nothing to be worst at, and a drill with
    /// an empty alphabet would send silence.
    @Test("'my worst' falls back to letters before you've been scored")
    func weakestFallsBack() {
        let characters = CharacterSetChoice.weakest.characters(scores: [:])
        #expect(characters == Morse.Alphabet.letters.characters)
    }
}

// MARK: - Callsigns

struct CallsignDrillTests {

    private func callsigns(_ count: Int = 6) -> [String] {
        CallsignDrill().makePrompt(context { $0.groupCount = count })
            .split(separator: " ").map(String.init)
    }

    @Test("every callsign has the shape of a callsign")
    func shape() {
        for call in callsigns(12) {
            #expect(call.count >= 3, "\(call) is too short to be a call")
            let hasDigit = call.contains { $0.isNumber }
            #expect(hasDigit, "\(call) has no digit")
            #expect(call.first?.isLetter == true, "\(call) doesn't start with a letter")
            #expect(call.last?.isLetter == true, "\(call) doesn't end with a suffix letter")
            let isAlphanumeric = call.allSatisfy { $0.isLetter || $0.isNumber }
            #expect(isAlphanumeric)
        }
    }

    @Test("the separating digit is inside the call, not on either end")
    func digitPosition() {
        for call in callsigns(12) {
            let digits = call.enumerated().filter { $0.element.isNumber }.map(\.offset)
            #expect(!digits.isEmpty)
            let inside = digits.allSatisfy { $0 > 0 && $0 < call.count - 1 }
            #expect(inside)
        }
    }

    @Test("the requested number of calls comes back")
    func count() {
        #expect(callsigns(1).count == 1)
        #expect(callsigns(7).count == 7)
    }

    /// A drill that sends the same call every round teaches that call.
    @Test("calls vary across a round")
    func variety() {
        #expect(Set(callsigns(12)).count > 1)
    }
}

// MARK: - QSO

struct QSODrillTests {

    @Test("prosigns are sent as prosigns, not as their letters")
    func prosignsSurvive() {
        // The bracket form has to reach the encoder intact, or <AR> goes out as
        // an A and an R with a gap between them — a different transmission.
        for phrase in QSODrill.phrases where phrase.hasPrefix("<") {
            let encoded = Morse.encode(phrase)
            #expect(encoded.tokens.count == 1, "\(phrase) didn't encode as one symbol")
            if case .prosign = encoded.tokens[0] {} else {
                Issue.record("\(phrase) encoded as \(encoded.tokens[0])")
            }
        }
    }

    @Test("every phrase in the table can actually be sent")
    func phrasesAreSendable() {
        for phrase in QSODrill.phrases {
            #expect(Morse.encode(phrase).isComplete, "\(phrase) contains something unsendable")
        }
    }

    @Test("a round draws several phrases")
    func drawsPhrases() {
        let prompt = QSODrill().makePrompt(context { $0.groupCount = 5 })
        #expect(!prompt.isEmpty)
        #expect(Morse.encode(prompt).isComplete)
    }
}

// MARK: - Custom text

struct CustomTextDrillTests {

    @Test("it sends a window of your text, not all of it at once")
    func windows() {
        let text = (1...40).map { "WORD\($0 % 10)" }.joined(separator: " ")
        let prompt = CustomTextDrill().makePrompt(context {
            $0.customText = text
            $0.groupCount = 3
        })

        #expect(prompt.split(separator: " ").count == 3)
    }

    @Test("text shorter than the window is sent whole rather than padded")
    func shortText() {
        let prompt = CustomTextDrill().makePrompt(context {
            $0.customText = "cq de"
            $0.groupCount = 5
        })

        #expect(prompt == "cq de")
    }

    @Test("empty text yields no prompt, so the session stays put")
    func emptyText() {
        let prompt = CustomTextDrill().makePrompt(context { $0.customText = "   " })
        #expect(prompt.isEmpty)
    }

    @Test("the window moves, so you don't drill the opening words forever")
    func windowMoves() {
        let text = (1...20).map { "W\($0)" }.joined(separator: " ")
        var seen = Set<String>()
        for step in 0..<8 {
            seen.insert(CustomTextDrill().makePrompt(context {
                $0.customText = text
                $0.groupCount = 2
                $0.randomIndex = { count in count == 0 ? 0 : (step * 3) % count }
            }))
        }
        #expect(seen.count > 1)
    }
}

// MARK: - Session wiring

@MainActor
struct DrillSessionTests {

    private final class MemoryStore: PracticeStoring {
        var level: Int?
        var characterWPM: Double?
        var effectiveWPM: Double?
        var scores: [Character: CharacterScore] = [:]
        var mode: String?
        var characterSet: String?
        var customText: String?
    }

    @Test("switching drills ends the round rather than marking it by new rules")
    func switchingModeClearsTheRound() {
        let session = PracticeSession(store: MemoryStore())
        session.startRound()
        session.finishedSending()
        session.answer = "KKKKK"

        session.mode = .callsigns

        #expect(session.phase == .ready)
        #expect(session.prompt.isEmpty)
        #expect(session.answer.isEmpty)
        #expect(session.grade == nil)
    }

    @Test("the ladder is Koch's alone")
    func advancementOnlyInKoch() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .callsigns
        session.startRound()
        session.answer = session.prompt
        session.submit()

        #expect(session.grade?.accuracy == 1.0)
        #expect(session.canAdvance == false)
        #expect(session.nextCharacter == nil)
    }

    @Test("prosign brackets are notation, so typing AR copies <AR>")
    func prosignBracketsAreNotGraded() {
        let grade = PracticeSession.grade(prompt: "TU <SK>", answer: "TU SK")

        #expect(grade.accuracy == 1.0)
        #expect(grade.total == 4)
    }

    @Test("the chosen drill survives a restart")
    func modePersists() {
        let store = MemoryStore()

        let first = PracticeSession(store: store)
        first.mode = .characterSet
        first.characterSet = .digits
        first.customText = "cq de w4abc"

        let second = PracticeSession(store: store)
        #expect(second.mode == .characterSet)
        #expect(second.characterSet == .digits)
        #expect(second.customText == "cq de w4abc")
    }
}
