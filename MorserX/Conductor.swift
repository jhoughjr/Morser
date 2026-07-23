//
//  Conductor.swift
//  MorserX
//
//  Created by Jimmy Hough Jr on 12/19/24.
//
//  Turns text into a tone sequence, hands the whole thing to the audio engine at
//  once, and then *follows* the audio clock to drive the UI.
//
//  The direction of that relationship is the point. The old loop played a tone,
//  awaited it, and updated the view — so every SwiftUI hitch became an audible
//  defect, and three MainActor hops per tone kept the view tree invalidating at
//  symbol rate. Now the audio is scheduled and immutable, and the UI asks it
//  where it got to. A slow frame can no longer bend the timing.
//

import Morse
import AudioKit
import AVFoundation

actor Conductor: ObservableObject {

    @MainActor @Published var isPlaying:Bool = false
    @MainActor @Published var playedTones:[SequencedTone] = []
    @MainActor @Published var unPlayedTones:[SequencedTone] = []
    @MainActor @Published var tones:[SequencedTone] = []
    @MainActor @Published var totalDuration:TimeInterval = 0.0
    @MainActor @Published var playedDuration:TimeInterval = 0.0
    @MainActor @Published var currentTone:SequencedTone? = nil
    @MainActor @Published var isSounding = false

    /// A sequenced tone knows its place.
    public struct SequencedTone: Equatable {
        let id:Int
        let tone:Tone
        let previous:Tone?
        let next:Tone?

        static func == (lhs: SequencedTone, rhs: SequencedTone) -> Bool {
            lhs.id == rhs.id
        }
    }

    nonisolated let player:Player = Player()
    var currentDitTime: Double = 0.2

    var playbackTask: Task<Void, Never>? = nil

    /// The sequence currently loaded, kept so a speed change mid-transmission can
    /// re-render the remainder without rebuilding it from text.
    private var loadedSequence: [SequencedTone] = []

    func setDitTime(_ time: Double) {
        guard time != currentDitTime else { return }
        self.currentDitTime = time

        guard !loadedSequence.isEmpty else { return }

        // Re-render from wherever the audio is now, so dragging the slider
        // retimes what hasn't been heard yet.
        if playbackTask != nil {
            let resumeAt = currentIndex() ?? 0
            schedule(from: resumeAt, ditTime: time)
        } else {
            // Idle: nothing to re-schedule, but the loaded sequence is what the
            // strip and its time ruler are drawn from, so it has to be retimed too.
            retimeLoadedSequence(to: time)
        }
    }

    /// Rebuilds the loaded sequence's durations at `ditTime`, keeping ids stable.
    private func retimeLoadedSequence(to ditTime: Double) {
        let retimed = loadedSequence.map { seq -> Tone in
            if let symbol = Morse.Symbols(rawValue: seq.tone.morse) {
                return Tone(symbol, ditTime: ditTime)
            }
            return seq.tone
        }
        let sequence = sequencedTones(for: retimed)
        loadedSequence = sequence

        let total = calculatedDuration(for: retimed)
        Task { @MainActor in
            self.tones = sequence
            self.unPlayedTones = sequence
            self.totalDuration = total
        }
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        player.stop()
        Task { @MainActor in
            self.isPlaying = false
            self.isSounding = false
        }
    }

    /// I should probably ensure i calulate from cleaned tones.
    private func calculatedDuration(for tones:[Tone]) -> TimeInterval {
        let duration = tones.reduce(0) { $0 + $1.duration }
        return duration
    }

    // should not use string but pass words

    /// Assembles tons from an input of Morse words.
    private func assembledTones(for input: String, ditTime: Double) -> [Tone] {
        var tones = [Tone]()

        let words = Morse.morseWords(from: input)
        let lastWordIndex = words.count - 1
        var unhandledCount = 0

        for (i,word) in words.enumerated() {
            let lastCharIndex = word.count - 1

            for (j,char) in word.enumerated() {
                switch char {
                case ".":
                    tones.append( .init(.dit, ditTime: ditTime))

                    if j != lastCharIndex {
                        tones.append(.init(.infraSpace, ditTime: ditTime))
                    }
                case "-":
                    tones.append(.init(.dah, ditTime: ditTime))
                    if j != lastCharIndex {
                        tones.append(.init(.infraSpace, ditTime: ditTime))
                    }
                default:
                    if unhandledCount % 3 == 0 {
                        tones.append(.init(.letterSpace, ditTime: ditTime))
                    }
                    unhandledCount += 1
                }
            }
            unhandledCount = 0
            if i != lastWordIndex {
                tones.append(.init(.wordSpace, ditTime: ditTime))
            }
        }
        return tones
    }

    /// Infra-spaces are not sounded to they need to be removed from the tone seuqence for proper timing.
    public func cleanedTones(for input: [Tone]) -> [Tone] {

        var previous: Tone? = nil
        var filteredInput: [Tone] = []

        input.forEach { i in
            if let p = previous {

                if p.morse == Morse.Symbols.infraSpace.rawValue {

                    if i.morse == Morse.Symbols.wordSpace.rawValue || i.morse == Morse.Symbols.letterSpace.rawValue {

                    }else {
                        filteredInput.append(p)

                    }
                }

                else {
                    filteredInput.append(p)

                }
            }

            //current is next previous
            previous = i
        }
        // adds the left previous tone
        if let p = previous {
            filteredInput.append(p)
        }

        return filteredInput
    }

    /// A sequnce is a linked list of Tones.
    public func sequencedTones(for input: [Tone]) -> [Conductor.SequencedTone] {
        var sequence = [Conductor.SequencedTone]()

        for (index, tone) in input.enumerated() {
            if index == 0 {
                sequence.append(Conductor.SequencedTone(id:index,
                                                        tone: tone,
                                                        previous: nil,
                                                        next: input.count > 1 ? input[index + 1] : nil))

            }else if index < input.count - 1 {

                sequence.append(Conductor.SequencedTone(id:index,
                                                        tone: tone,
                                                        previous: input[index - 1],
                                                        next: input[index + 1]))

            }else if index == input.count - 1 {
                sequence.append(Conductor.SequencedTone(id:index,
                                                        tone: tone,
                                                        previous: input[index - 1],
                                                        next: nil))
            }
        }
        return sequence
    }

    /// Builds the tone sequence for `morse` and publishes it *without* playing.
    ///
    /// The sequencer strip reads `tones`, so this is what lets it fill in as you
    /// type. Loading used to be welded to playback, which meant the strip stayed
    /// empty — showing its "type text above" placeholder over perfectly good
    /// text — until you pressed Play.
    /// - Parameter morse: The morse code string to sequence.
    /// - Parameter ditTime: The unit duration (in seconds) for a "dit".
    public func load(morse: String,
                     with ditTime: Double = 0.2) {
        // Retyping mid-transmission invalidates what the engine is sounding.
        if playbackTask != nil { stop() }

        self.currentDitTime = ditTime

        let input = morse.trimmingCharacters(in: .whitespacesAndNewlines)
        let sequence = self.sequencedTones(for: self.cleanedTones(for: assembledTones(for: input,
                                                                                      ditTime: ditTime)))
        self.loadedSequence = sequence

        let total = calculatedDuration(for: sequence.map(\.tone))
        Task { @MainActor in
            self.tones = sequence
            self.playedTones.removeAll()
            self.unPlayedTones = sequence
            self.playedDuration = 0
            self.totalDuration = total
            self.currentTone = nil
        }
    }

    /// Sounds `morse` without loading it into the sequencer.
    ///
    /// Practice needs the audio and nothing else: putting the prompt in the strip
    /// would answer the question it is asking. The published state this touches is
    /// `isPlaying` only, so the strip keeps showing whatever text was there.
    /// - Parameter spaceDitTime: unit length for the *gaps*, when it differs from
    ///   the characters' — Farnsworth spacing.
    public func send(morse: String,
                     with ditTime: Double,
                     spaceDitTime: Double? = nil) {
        stop()

        let input = morse.trimmingCharacters(in: .whitespacesAndNewlines)
        var tones = cleanedTones(for: assembledTones(for: input, ditTime: ditTime))
        if let spacing = spaceDitTime {
            tones = farnsworthed(tones, spaceDitTime: spacing)
        }

        let spans = player.play(tones: tones)
        guard let last = spans.last else { return }

        Task { @MainActor in self.isPlaying = true }
        playbackTask = Task { [weak self] in
            await self?.followSilently(untilFrame: last.endFrame)
        }
    }

    /// Builds tones straight from the text, one character at a time, so each can
    /// carry its own pitch.
    ///
    /// The string-based path can't do this: by the time text is a run of dots and
    /// dashes, which symbol belongs to which character is only recoverable by
    /// counting spaces in threes. Here the characters are still characters.
    func pitchedTones(for text: String,
                      ditTime: Double,
                      spaceDitTime: Double? = nil,
                      pitch: (Character) -> Float?) -> [Tone] {
        var tones: [Tone] = []
        let spacing = spaceDitTime ?? ditTime

        for (wordIndex, word) in text.split(separator: " ").enumerated() {
            if wordIndex > 0 { tones.append(Tone(.wordSpace, ditTime: spacing)) }

            for (characterIndex, character) in word.enumerated() {
                guard let code = Morse.code(for: character) else { continue }
                if characterIndex > 0 { tones.append(Tone(.letterSpace, ditTime: spacing)) }

                // Uppercased, so a caller's table doesn't have to hold both cases.
                let note = pitch(Character(String(character).uppercased()))
                for (symbolIndex, symbol) in code.enumerated() {
                    if symbolIndex > 0 { tones.append(Tone(.infraSpace, ditTime: ditTime)) }
                    tones.append(Tone(symbol == "." ? .dit : .dah, ditTime: ditTime, pitch: note))
                }
            }
        }
        return tones
    }

    /// Sounds text with a pitch per character, without loading the sequencer.
    public func sing(_ text: String,
                     ditTime: Double,
                     spaceDitTime: Double? = nil,
                     pitch: @escaping (Character) -> Float?) {
        stop()

        let tones = pitchedTones(for: text, ditTime: ditTime, spaceDitTime: spaceDitTime, pitch: pitch)
        let spans = player.play(tones: tones)
        guard let last = spans.last else { return }

        Task { @MainActor in self.isPlaying = true }
        playbackTask = Task { [weak self] in
            await self?.followSilently(untilFrame: last.endFrame)
        }
    }

    /// Suspends until whatever is currently sounding has finished.
    public func waitForSending() async {
        await playbackTask?.value
    }

    /// Stretches only the inter-character and inter-word gaps.
    ///
    /// The characters keep their real rhythm, which is the whole point of
    /// Farnsworth timing — slowing the dits themselves would teach a rhythm that
    /// doesn't exist at speed.
    func farnsworthed(_ tones: [Tone], spaceDitTime: Double) -> [Tone] {
        tones.map { tone in
            switch tone.morse {
            case Morse.Symbols.letterSpace.rawValue: return Tone(.letterSpace, ditTime: spaceDitTime)
            case Morse.Symbols.wordSpace.rawValue:   return Tone(.wordSpace, ditTime: spaceDitTime)
            default:                                 return tone
            }
        }
    }

    /// Follows the clock just far enough to know when the sending has finished.
    private func followSilently(untilFrame total: Int) async {
        var ticksWaitingForFirstFrame = 0
        let bootstrapLimit = 500   // ~2s at 4ms

        while !Task.isCancelled {
            guard let frame = player.currentFrame else {
                ticksWaitingForFirstFrame += 1
                if ticksWaitingForFirstFrame > bootstrapLimit { break }
                try? await Task.sleep(for: .milliseconds(4))
                continue
            }
            ticksWaitingForFirstFrame = 0
            if frame >= total { break }
            try? await Task.sleep(for: .milliseconds(8))
        }

        guard !Task.isCancelled else { return }
        await MainActor.run {
            self.isPlaying = false
            self.isSounding = false
        }
        playbackTask = nil
    }

    /// Top level API to turn morse strings into played tones.
    /// - Parameter morse: The morse code string to play.
    /// - Parameter ditTime: The unit duration (in seconds) for a "dit". This parameter is now fully respected for all playback unit durations.
    public func sound(morse: String,
                      with ditTime: Double = 0.2)   {
        load(morse: morse, with: ditTime)
        schedule(from: 0, ditTime: ditTime)
    }

    // MARK: - Scheduling

    /// Renders the tail of the sequence at `ditTime` and hands it to the engine in one
    /// scheduling call, then starts following the clock.
    private func schedule(from index: Int, ditTime: Double) {
        playbackTask?.cancel()

        guard index < loadedSequence.count else {
            stop()
            return
        }

        // Rebuild the remaining tones at the current speed. Durations are the only
        // thing that changes, so the sequence identity (and the UI's ids) survive.
        let remaining = loadedSequence[index...].map { seq -> Tone in
            if let symbol = Morse.Symbols(rawValue: seq.tone.morse) {
                return Tone(symbol, ditTime: ditTime)
            }
            return seq.tone
        }

        let spans = player.play(tones: remaining)
        guard !spans.isEmpty else {
            stop()
            return
        }

        Task { @MainActor in self.isPlaying = true }

        playbackTask = Task { [weak self] in
            await self?.follow(spans: spans, offset: index)
        }
    }

    /// Index into `loadedSequence` that the audio hardware is currently sounding.
    private var scheduleOffset: Int = 0
    private var currentSpans: [ToneSpan] = []

    private func currentIndex() -> Int? {
        guard let frame = player.currentFrame else { return nil }
        var index = 0
        while index + 1 < currentSpans.count && currentSpans[index + 1].startFrame <= frame {
            index += 1
        }
        return scheduleOffset + index
    }

    /// Polls the audio clock and mirrors it into the published state.
    ///
    /// Polling here is safe in a way it wasn't before: this loop only *reads* the
    /// clock, so if a poll runs late the UI catches up on the next tick and the
    /// audio is entirely unaffected.
    private func follow(spans: [ToneSpan], offset: Int) async {
        currentSpans = spans
        scheduleOffset = offset

        let sampleRate = player.renderer.sampleRate
        let total = spans.last?.endFrame ?? 0
        let started = Date()
        var lastIndex = -1

        // If the engine never renders — no output device, engine failed to start —
        // give up rather than poll forever with isPlaying stuck on.
        var ticksWaitingForFirstFrame = 0
        let bootstrapLimit = 500   // ~2s at 4ms

        while !Task.isCancelled {
            guard let frame = player.currentFrame else {
                // The node is scheduled but hasn't rendered its first buffer yet.
                ticksWaitingForFirstFrame += 1
                if ticksWaitingForFirstFrame > bootstrapLimit { break }
                try? await Task.sleep(for: .milliseconds(4))
                continue
            }
            ticksWaitingForFirstFrame = 0

            if frame >= total { break }

            var index = max(lastIndex, 0)
            while index + 1 < spans.count && spans[index + 1].startFrame <= frame {
                index += 1
            }

            if index != lastIndex {
                // Claim every tone we passed, not just the current one — at high speed
                // a poll interval can span several elements.
                let passed = ((lastIndex + 1)...index).compactMap { i -> SequencedTone? in
                    let position = offset + i
                    return position < loadedSequence.count ? loadedSequence[position] : nil
                }
                let sounding = spans[index].isSounding
                let currentPosition = offset + index
                let current = currentPosition < loadedSequence.count ? loadedSequence[currentPosition] : nil

                await MainActor.run {
                    self.currentTone = current
                    self.isSounding = sounding
                    self.playedTones.append(contentsOf: passed)
                    let passedIDs = Set(passed.map(\.id))
                    self.unPlayedTones.removeAll { passedIDs.contains($0.id) }
                }
                lastIndex = index
            }

            try? await Task.sleep(for: .milliseconds(8))
        }

        guard !Task.isCancelled else { return }

        let elapsed = Date().timeIntervalSince(started)
        let rendered = Double(total) / sampleRate
        await MainActor.run {
            self.isPlaying = false
            self.isSounding = false
            self.currentTone = nil
            self.playedDuration = rendered > 0 ? rendered : elapsed
        }
        playbackTask = nil
    }
}
