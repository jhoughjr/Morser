//
//  PracticePhaseTwoThreeTests.swift
//  MorserXTests
//
//  Words, head copy, and instant recognition.
//
//  These three break assumptions the earlier drills could rely on: head copy has
//  no typed answer to compare against, instant recognition is scored on how long
//  you took rather than only on whether you were right, and the speed ladder
//  changes the session's settings from inside the grading. All three are places
//  where the screen would look perfectly reasonable while the record underneath
//  it was wrong.
//

import Testing
import Foundation
import Morse
@testable import MorserX

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

private func context(_ mutate: (inout DrillContext) -> Void = { _ in }) -> DrillContext {
    var context = DrillContext()
    var step = 0
    context.randomIndex = { count in
        defer { step += 1 }
        return count == 0 ? 0 : step % count
    }
    mutate(&context)
    return context
}

// MARK: - Words

struct WordsDrillTests {

    @Test("the vocabulary is entirely sendable")
    func vocabularyIsSendable() {
        for word in CommonWords.english + CommonWords.radio {
            let encoded = Morse.encode(word)
            #expect(encoded.isComplete, "\(word) contains \(encoded.skipped), which can't be sent")
            #expect(!encoded.morse.isEmpty, "\(word) encoded to nothing")
        }
    }

    @Test("the vocabulary is big enough not to repeat itself at you")
    func vocabularySize() {
        #expect(CommonWords.english.count >= 300)
        #expect(CommonWords.radio.count >= 30)
        #expect(Set(CommonWords.english).count == CommonWords.english.count)
    }

    @Test("a round is the requested number of words")
    func promptShape() {
        let prompt = WordsDrill().makePrompt(context { $0.groupCount = 4 })
        #expect(prompt.split(separator: " ").count == 4)
    }

    @Test("words come from the vocabulary, not from thin air")
    func promptDrawsFromVocabulary() {
        let vocabulary = Set(CommonWords.english + CommonWords.radio)
        let prompt = WordsDrill().makePrompt(context { $0.groupCount = 8 })

        for word in prompt.split(separator: " ") {
            #expect(vocabulary.contains(String(word)), "\(word) isn't in the list")
        }
    }
}

// MARK: - Head copy

struct HeadCopyDrillTests {

    @Test("head copy sends one word — two would be a memory test")
    func singleWord() {
        for _ in 0..<10 {
            let prompt = HeadCopyDrill().makePrompt(context())
            #expect(!prompt.isEmpty)
            #expect(prompt.split(separator: " ").count == 1)
        }
    }

    @Test("there is nothing to type into")
    func answerMethod() {
        #expect(HeadCopyDrill().answerMethod == .selfReported)
        #expect(HeadCopyDrill().answerDeadline == nil)
    }

    /// The whole word stands or falls together: hearing four letters of a
    /// five-letter word is not having copied it.
    @Test("saying you got it scores the whole word, and missing it scores none")
    func selfReportedGrading() {
        let got = PracticeSession.selfReportedGrade(prompt: "THE", copied: true)
        #expect(got.total == 3)
        #expect(got.hits == 3)
        #expect(got.accuracy == 1.0)

        let missed = PracticeSession.selfReportedGrade(prompt: "THE", copied: false)
        #expect(missed.total == 3)
        #expect(missed.hits == 0)
        #expect(missed.accuracy == 0)
    }

    @MainActor
    @Test("a self-reported round still updates the per-character record")
    func selfReportFeedsTheRecord() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .headCopy
        session.startRound()
        session.finishedSending()

        let prompt = session.prompt
        session.submit(selfReported: true)

        for character in Set(prompt.uppercased()) where !character.isWhitespace {
            #expect(session.scores[character]?.hits ?? 0 > 0,
                    "\(character) wasn't credited")
        }
    }
}

// MARK: - Instant recognition

struct InstantDrillTests {

    @Test("instant recognition sends exactly one character")
    func singleCharacter() {
        for _ in 0..<10 {
            let prompt = InstantDrill().makePrompt(context { $0.level = 8 })
            #expect(prompt.count == 1)
        }
    }

    @Test("it draws from what you've unlocked, not the whole mode")
    func staysInAlphabet() {
        let drill = InstantDrill()
        let ctx = context { $0.level = 5 }
        let allowed = Set(drill.alphabet(ctx))

        for _ in 0..<20 {
            #expect(Set(drill.makePrompt(ctx)).isSubset(of: allowed))
        }
    }

    @Test("it is answered with one key, against a clock")
    func answerShape() {
        let drill = InstantDrill()
        #expect(drill.answerMethod == .singleKey)
        #expect(drill.answerDeadline != nil)
        #expect(drill.measuresLatency)
    }

    @MainActor
    @Test("a right answer is timed")
    func latencyRecorded() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .instant
        session.startRound()
        session.finishedSending()

        let prompt = session.prompt
        session.answer = prompt
        session.submit()

        let character = Character(prompt.uppercased())
        #expect(session.scores[character]?.latencySamples == 1)
        #expect(session.lastLatency != nil)
    }

    /// How long it took to get it wrong is not a speed, and averaging it in
    /// would make a bad round look like a slow one.
    @MainActor
    @Test("a wrong answer is not timed")
    func missesAreNotTimed() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .instant
        session.startRound()
        session.finishedSending()

        let prompt = session.prompt
        session.answer = prompt == "K" ? "M" : "K"
        session.submit()

        let character = Character(prompt.uppercased())
        #expect(session.scores[character]?.attempts == 1)
        #expect(session.scores[character]?.latencySamples == 0)
    }

    @MainActor
    @Test("drills that aren't timed don't record a time")
    func typedDrillsAreNotTimed() {
        let session = PracticeSession(store: MemoryStore())
        session.mode = .koch
        session.startRound()
        session.finishedSending()
        session.answer = session.prompt
        session.submit()

        #expect(session.lastLatency == nil)
        #expect(session.scores.values.allSatisfy { $0.latencySamples == 0 })
    }

    @Test("an average appears only once there's something to average")
    func averageLatency() {
        var score = CharacterScore(attempts: 1, hits: 1)
        #expect(score.averageLatency == nil)

        score.latencyMillis = 900
        score.latencySamples = 2
        #expect(score.averageLatency == 0.45)
    }
}

// MARK: - Speed ladder

@MainActor
struct SpeedLadderTests {

    private func cleanRound(_ session: PracticeSession) {
        session.startRound()
        session.finishedSending()
        session.answer = session.prompt
        session.submit()
    }

    @Test("off by default — nobody's speed should change without asking")
    func offByDefault() {
        let session = PracticeSession(store: MemoryStore())
        #expect(session.speedLadder == false)

        let before = session.characterWPM
        for _ in 0..<6 { cleanRound(session) }
        #expect(session.characterWPM == before)
    }

    @Test("a run of clean rounds earns one word per minute")
    func raisesSpeed() {
        let session = PracticeSession(store: MemoryStore())
        session.speedLadder = true
        let before = session.characterWPM

        for _ in 0..<PracticeSession.ladderStreak { cleanRound(session) }

        #expect(session.characterWPM == before + 1)
        // The streak was earned at the old speed, so it says nothing about the new one.
        #expect(session.streak == 0)
    }

    @Test("a bad round breaks the run rather than banking it")
    func missResetsTheRun() {
        let session = PracticeSession(store: MemoryStore())
        session.speedLadder = true
        session.groupCount = 1
        session.groupSize = 4
        let before = session.characterWPM

        cleanRound(session)
        session.startRound()
        session.finishedSending()
        session.answer = ""
        session.submit()
        cleanRound(session)

        #expect(session.characterWPM == before)
        #expect(session.streak == 1)
    }

    @Test("the ladder stops at the top rather than running away")
    func capped() {
        let session = PracticeSession(store: MemoryStore())
        session.speedLadder = true
        session.characterWPM = PracticeSession.maximumWPM

        for _ in 0..<(PracticeSession.ladderStreak * 3) { cleanRound(session) }

        #expect(session.characterWPM == PracticeSession.maximumWPM)
    }

    @Test("the setting survives a restart")
    func persists() {
        let store = MemoryStore()
        PracticeSession(store: store).speedLadder = true
        #expect(PracticeSession(store: store).speedLadder)
    }
}

// MARK: - Store migration

@MainActor
struct ScoreMigrationTests {

    /// Rows written before latency existed have two columns. Discarding them
    /// would quietly wipe someone's record on upgrade.
    @Test("a record written before latency existed is read, not dropped")
    func oldRowsSurvive() {
        let defaults = UserDefaults(suiteName: "morserx.tests.migration")!
        defaults.removePersistentDomain(forName: "morserx.tests.migration")
        defaults.set(["K": [10, 9], "M": [4, 2]], forKey: "practice.scores")

        let store = UserDefaultsPracticeStore(defaults: defaults)

        #expect(store.scores["K"] == CharacterScore(attempts: 10, hits: 9))
        #expect(store.scores["M"]?.averageLatency == nil)

        defaults.removePersistentDomain(forName: "morserx.tests.migration")
    }

    @Test("latency round-trips through the store")
    func latencyRoundTrips() {
        let defaults = UserDefaults(suiteName: "morserx.tests.latency")!
        defaults.removePersistentDomain(forName: "morserx.tests.latency")

        let store = UserDefaultsPracticeStore(defaults: defaults)
        store.scores = ["Q": CharacterScore(attempts: 5, hits: 4, latencyMillis: 2000, latencySamples: 4)]

        #expect(store.scores["Q"]?.averageLatency == 0.5)

        defaults.removePersistentDomain(forName: "morserx.tests.latency")
    }
}
