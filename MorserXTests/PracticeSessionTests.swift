//
//  PracticeSessionTests.swift
//  MorserXTests
//
//  Practice is graded work, so the grading is what has to be right. These pin
//  the parts a screenshot can't show: which characters can appear at a level,
//  how a dropped character is scored, when the next character is unlocked, and
//  that Farnsworth spacing degenerates to plain timing when the two speeds match.
//

import Testing
import Foundation
import Morse
@testable import MorserX

// MARK: - Doubles

/// In-memory stand-in so tests never touch the user's real progress.
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

@MainActor
private func makeSession(store: PracticeStoring = MemoryStore(),
                         picks: [Int] = []) -> PracticeSession {
    let session = PracticeSession(store: store)
    if !picks.isEmpty {
        var index = 0
        session.randomIndex = { _ in
            defer { index += 1 }
            return picks[index % picks.count]
        }
    }
    return session
}

// MARK: - Alphabet & progression

@MainActor
struct PracticeAlphabetTests {

    @Test("a fresh session starts at two characters, per Koch")
    func startsAtTwo() {
        let session = makeSession()

        #expect(session.level == 2)
        #expect(session.alphabet == ["K", "M"])
        #expect(session.nextCharacter == "R")
    }

    @Test("the level is clamped to the ladder at both ends")
    func levelClamped() {
        let session = makeSession()

        session.level = 0
        #expect(session.level == 2)

        session.level = 999
        #expect(session.level == PracticeSession.kochOrder.count)
        #expect(session.nextCharacter == nil)
    }

    @Test("a prompt only ever contains characters that are in play")
    func promptStaysInAlphabet() {
        let session = makeSession()
        session.level = 6

        for _ in 0..<25 {
            session.startRound()
            let used = Set(session.prompt.filter { !$0.isWhitespace })
            #expect(used.isSubset(of: Set(session.alphabet)))
        }
    }

    @Test("the prompt is laid out as the requested number of groups")
    func promptShape() {
        let session = makeSession(picks: [0])
        session.groupCount = 4
        session.groupSize = 5

        session.startRound()

        let groups = session.prompt.split(separator: " ")
        #expect(groups.count == 4)
        #expect(groups.allSatisfy { $0.count == 5 })
        // picks: [0] always chooses the first character in play.
        #expect(session.prompt == "KKKKK KKKKK KKKKK KKKKK")
    }

    @Test("a round can be encoded — nothing in the Koch set is unsendable")
    func everyCharacterEncodes() {
        for char in PracticeSession.kochOrder {
            #expect(!Morse.morse(from: String(char)).isEmpty,
                    "\(char) produced no morse")
        }
    }

    @Test("sending is a gate: the copy isn't accepted until the audio ends")
    func phaseGate() {
        let session = makeSession(picks: [0])

        #expect(session.phase == .ready)
        session.startRound()
        #expect(session.phase == .sending)
        session.finishedSending()
        #expect(session.phase == .answering)
        session.submit()
        #expect(session.phase == .graded)
    }
}

// MARK: - Grading

@MainActor
struct PracticeGradingTests {

    @Test("a perfect copy is 100%")
    func perfect() {
        let grade = PracticeSession.grade(prompt: "KMRS KMRS", answer: "kmrs kmrs")

        #expect(grade.total == 8)
        #expect(grade.hits == 8)
        #expect(grade.accuracy == 1.0)
    }

    @Test("one wrong character costs exactly one character")
    func oneWrong() {
        let grade = PracticeSession.grade(prompt: "KMRS", answer: "KMRT")

        #expect(grade.total == 4)
        #expect(grade.hits == 3)
        #expect(grade.cells.last?.expected == "S")
        #expect(grade.cells.last?.heard == "T")
    }

    @Test("a dropped character doesn't shift the rest of the group into failure")
    func droppedCharacterIsContained() {
        // "M" missed; a whole-string positional compare would then mark R and S
        // wrong too, and the score would read 25% for a single mistake.
        let grade = PracticeSession.grade(prompt: "KMRS", answer: "KRS")

        #expect(grade.total == 4)
        #expect(grade.hits == 1)   // only K lands; the tail is shifted
        #expect(grade.cells[3].isMissed)
    }

    @Test("a dropped character in group one leaves group two intact")
    func damageStopsAtTheGroupBoundary() {
        let grade = PracticeSession.grade(prompt: "KMRS KMRS", answer: "KRS KMRS")

        #expect(grade.total == 8)
        // Second group is copied perfectly regardless of what happened in the first.
        #expect(grade.groups[1].allSatisfy { $0.isHit })
    }

    @Test("typing more than was sent counts as extra, not as credit")
    func extraCharacters() {
        let grade = PracticeSession.grade(prompt: "KM", answer: "KMRS")

        #expect(grade.total == 2)
        #expect(grade.hits == 2)
        #expect(grade.accuracy == 1.0)
        #expect(grade.cells.filter(\.isExtra).count == 2)
    }

    @Test("an empty copy scores zero rather than dividing by zero")
    func emptyAnswer() {
        let grade = PracticeSession.grade(prompt: "KMRS", answer: "")

        #expect(grade.total == 4)
        #expect(grade.hits == 0)
        #expect(grade.accuracy == 0)
    }

    @Test("nothing sent is not a perfect score")
    func emptyPrompt() {
        let grade = PracticeSession.grade(prompt: "", answer: "")

        #expect(grade.total == 0)
        #expect(grade.accuracy == 0)
    }
}

// MARK: - Scores & advancement

@MainActor
struct PracticeScoringTests {

    @Test("submitting folds the round into the per-character record")
    func scoresAccumulate() {
        let session = makeSession(picks: [0])
        session.groupCount = 1
        session.groupSize = 4

        session.startRound()            // KKKK
        session.answer = "KKMK"
        session.submit()

        #expect(session.scores["K"] == CharacterScore(attempts: 4, hits: 3))
        // M was never sent, so it has no record — being typed by mistake isn't an attempt.
        #expect(session.scores["M"] == nil)
    }

    @Test("the next character unlocks at the accuracy threshold, not below it")
    func advancement() {
        let session = makeSession(picks: [0])
        session.groupCount = 1
        session.groupSize = 10

        session.startRound()
        session.answer = "KKKKKKKKMM"   // 8/10
        session.submit()
        #expect(session.canAdvance == false)

        session.startRound()
        session.answer = "KKKKKKKKKM"   // 9/10 — exactly the bar
        session.submit()
        #expect(session.canAdvance)

        let before = session.level
        session.advance()
        #expect(session.level == before + 1)
    }

    @Test("advancement is refused at the top of the ladder")
    func noAdvanceAtTheTop() {
        let session = makeSession(picks: [0])
        session.level = PracticeSession.kochOrder.count
        session.groupCount = 1
        session.groupSize = 2

        session.startRound()
        session.answer = session.prompt
        session.submit()

        #expect(session.grade?.accuracy == 1.0)
        #expect(session.canAdvance == false)
    }

    @Test("the newest character is drilled harder than the settled ones")
    func newestIsWeighted() {
        let session = makeSession()
        session.level = 6                       // K M R S U A — A is newest

        let bag = session.weightedBag
        let newest = bag.filter { $0 == "A" }.count
        let oldest = bag.filter { $0 == "K" }.count

        #expect(newest > oldest)
        // Nothing is dropped: drilling only the weak ones would let the rest rot.
        #expect(Set(bag) == Set(session.alphabet))
    }

    @Test("a character you keep missing turns up more often")
    func weakCharactersAreWeighted() {
        let store = MemoryStore()
        store.level = 6
        store.scores = [
            "K": CharacterScore(attempts: 20, hits: 4),    // badly wrong
            "M": CharacterScore(attempts: 20, hits: 20)    // solid
        ]
        let session = makeSession(store: store)

        let bag = session.weightedBag
        #expect(bag.filter { $0 == "K" }.count > bag.filter { $0 == "M" }.count)
    }

    @Test("a character with barely any history isn't reweighted on noise")
    func weightingWaitsForEvidence() {
        let store = MemoryStore()
        store.level = 6
        store.scores = ["K": CharacterScore(attempts: 2, hits: 0)]
        let session = makeSession(store: store)

        let bag = session.weightedBag
        #expect(bag.filter { $0 == "K" }.count == bag.filter { $0 == "M" }.count)
    }

    @Test("session totals and the streak track the rounds actually taken")
    func sessionStats() {
        let session = makeSession(picks: [0])
        session.groupCount = 1
        session.groupSize = 10

        session.startRound()
        session.answer = session.prompt          // clean
        session.submit()
        #expect(session.streak == 1)
        #expect(session.sessionAccuracy == 1.0)

        session.startRound()
        session.answer = ""                      // nothing copied
        session.submit()
        #expect(session.streak == 0)
        #expect(session.roundsThisSession == 2)
        #expect(session.sessionTotal == 20)
        #expect(session.sessionHits == 10)
        #expect(session.sessionAccuracy == 0.5)
    }

    @Test("unlocking a character clears the streak it was not earned on")
    func advancingResetsStreak() {
        let session = makeSession(picks: [0])
        session.groupCount = 1
        session.groupSize = 4

        session.startRound()
        session.answer = session.prompt
        session.submit()
        #expect(session.streak == 1)

        session.advance()
        #expect(session.streak == 0)
    }

    @Test("weakest lists only characters actually heard, worst first")
    func weakestOrdering() {
        let store = MemoryStore()
        store.level = 6
        store.scores = [
            "K": CharacterScore(attempts: 10, hits: 9),
            "M": CharacterScore(attempts: 10, hits: 3),
            "R": CharacterScore(attempts: 10, hits: 6),
            "Z": CharacterScore(attempts: 10, hits: 1)   // not in play at level 6
        ]
        let session = makeSession(store: store)

        let order = session.weakest.map(\.character)
        #expect(order == ["M", "R", "K"])
    }

    @Test("progress and speed survive a restart")
    func persistence() {
        let store = MemoryStore()

        let first = makeSession(store: store, picks: [0])
        first.level = 9
        first.characterWPM = 22
        first.effectiveWPM = 12
        first.groupCount = 1
        first.groupSize = 2
        first.startRound()
        first.answer = first.prompt
        first.submit()

        let second = makeSession(store: store)
        #expect(second.level == 9)
        #expect(second.characterWPM == 22)
        #expect(second.effectiveWPM == 12)
        #expect(second.scores.isEmpty == false)
    }

    @Test("the spacing speed can't outrun the character speed")
    func effectiveSpeedClamped() {
        let session = makeSession()
        session.characterWPM = 25
        session.effectiveWPM = 20

        session.characterWPM = 15

        #expect(session.effectiveWPM == 15)
    }

    @Test("resetting clears the record in the store, not just in memory")
    func resetScores() {
        let store = MemoryStore()
        store.scores = ["K": CharacterScore(attempts: 5, hits: 5)]
        let session = makeSession(store: store)

        session.resetScores()

        #expect(session.scores.isEmpty)
        #expect(store.scores.isEmpty)
    }
}

// MARK: - Conductor spacing

struct FarnsworthTonesTests {

    @Test("only the space tones are retimed; dits and dahs keep their length")
    func onlySpacesStretch() async {
        let conductor = Conductor()
        let dit = 0.06
        let wide = 0.18

        let tones: [Tone] = [
            Tone(.dit, ditTime: dit),
            Tone(.infraSpace, ditTime: dit),
            Tone(.dah, ditTime: dit),
            Tone(.letterSpace, ditTime: dit),
            Tone(.wordSpace, ditTime: dit)
        ]

        let result = await conductor.farnsworthed(tones, spaceDitTime: wide)

        #expect(result[0].duration == dit)          // dit
        #expect(result[1].duration == dit)          // intra-character space stays tight
        #expect(result[2].duration == dit * 3)      // dah
        #expect(result[3].duration == wide * 3)     // letter gap stretched
        #expect(result[4].duration == wide * 7)     // word gap stretched
    }
}
