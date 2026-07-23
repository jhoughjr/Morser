//
//  StripLayoutTests.swift
//  MorserXTests
//
//  The strip is a timing diagram, so its geometry is a claim about time: a dah is
//  three times a dit, a word gap is seven, and the letter under a group belongs to
//  the bars above it. Those are the things that can be quietly wrong on screen —
//  a picture that's merely plausible still looks fine.
//

import Testing
import Foundation
import Morse
@testable import MorserX

@MainActor
struct StripLayoutTests {

    /// Builds the same sequence the conductor would, so the layout is tested
    /// against real tone data rather than a hand-made approximation.
    private func layout(for text: String, ditTime: Double = 0.1, unit: CGFloat = 9) async -> StripLayout.Model {
        let conductor = Conductor()
        let morse = Morse.morse(from: text)
        await conductor.load(morse: morse, with: ditTime)
        try? await Task.sleep(for: .milliseconds(120))

        let letters = Array(text.uppercased().filter { !$0.isWhitespace })
        return StripLayout.build(tones: conductor.tones, letters: letters, unit: unit)
    }

    @Test("nothing in, nothing out")
    func empty() {
        let model = StripLayout.build(tones: [], letters: [], unit: 9)

        #expect(model.bars.isEmpty)
        #expect(model.groups.isEmpty)
        #expect(model.width == 0)
    }

    @Test("only sounded tones get a bar — silence is space, not ink")
    func silenceHasNoBars() async {
        // E is one dit; the letter gap and the second E follow.
        let model = await layout(for: "ee")

        #expect(model.bars.count == 2)
        #expect(model.groups.count == 2)
    }

    @Test("a dah is drawn three times the width of a dit")
    func dahIsThreeDits() async {
        // A is dit-dah.
        let model = await layout(for: "a")

        #expect(model.bars.count == 2)
        let dit = model.bars[0]
        let dah = model.bars[1]
        #expect(dah.isDah)
        #expect(!dit.isDah)
        #expect(abs(dah.width - dit.width * 3) < 0.001)
    }

    @Test("bars are laid end to end with the gaps between them, never overlapping")
    func barsDoNotOverlap() async {
        let model = await layout(for: "hello world")

        for (a, b) in zip(model.bars, model.bars.dropFirst()) {
            #expect(b.x >= a.x + a.width - 0.001,
                    "bar \(b.id) starts before bar \(a.id) ends")
        }
        #expect(model.width >= (model.bars.last.map { $0.x + $0.width } ?? 0))
    }

    @Test("the gap inside a character is one dit and the gap between them is three")
    func gapsAreToScale() async {
        // "EE": dit, letter gap, dit. The gap between the two bars is the letter gap.
        let ee = await layout(for: "ee")
        let ditWidth = ee.bars[0].width
        let letterGap = ee.bars[1].x - (ee.bars[0].x + ee.bars[0].width)
        #expect(abs(letterGap - ditWidth * 3) < 0.001)

        // "I" is dit-dit: the gap inside a character is a single dit.
        let i = await layout(for: "i")
        let intraGap = i.bars[1].x - (i.bars[0].x + i.bars[0].width)
        #expect(abs(intraGap - ditWidth) < 0.001)
    }

    @Test("each group carries the letter it spells, in order")
    func groupsCarryTheirLetters() async {
        let model = await layout(for: "sos")

        #expect(model.groups.count == 3)
        #expect(model.groups.map(\.letter) == ["S", "O", "S"])
        // S is three dits, O is three dahs.
        #expect(model.groups[0].ids.count == 3)
        #expect(model.groups[1].ids.count == 3)
    }

    @Test("a group spans exactly its own bars")
    func groupBoundsCoverTheirBars() async {
        let model = await layout(for: "sos")

        for group in model.groups {
            let owned = model.bars.filter { group.ids.contains($0.id) }
            #expect(!owned.isEmpty)
            #expect(group.x <= (owned.first?.x ?? 0) + 0.001)
            let end = owned.map { $0.x + $0.width }.max() ?? 0
            #expect(group.x + group.width >= end - 0.001)
        }
    }

    @Test("word gaps are marked once each, between the words")
    func wordBreaks() async {
        let model = await layout(for: "hello world")

        #expect(model.wordBreaks.count == 1)
        // Every group still belongs to one word or the other, and the break sits
        // between the two.
        let firstWordEnd = model.groups[4].x + model.groups[4].width   // "o" of hello
        let secondWordStart = model.groups[5].x                        // "w" of world
        let breakX = model.wordBreaks[0]
        #expect(breakX > firstWordEnd)
        #expect(breakX < secondWordStart)
    }

    @Test("groups outnumbered by tones don't reach past the letters they were given")
    func fewerLettersThanGroups() async {
        let conductor = Conductor()
        await conductor.load(morse: Morse.morse(from: "sos"), with: 0.1)
        try? await Task.sleep(for: .milliseconds(120))

        let model = StripLayout.build(tones: conductor.tones, letters: ["S"], unit: 9)

        #expect(model.groups.count == 3)
        #expect(model.groups[0].letter == "S")
        #expect(model.groups[1].letter == nil)
        #expect(model.groups[2].letter == nil)
    }

    @Test("the scale is honest: a second of morse is pointsPerSecond wide")
    func scaleMatchesTime() async {
        let ditTime = 0.08
        let model = await layout(for: "hello world", ditTime: ditTime, unit: 9)

        let expectedPerSecond = 9 / ditTime
        #expect(abs(Double(model.pointsPerSecond) - expectedPerSecond) < 0.001)
    }
}
