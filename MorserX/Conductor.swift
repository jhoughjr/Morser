//
//  Conductor.swift
//  MorserX
//
//  Created by Jimmy Hough Jr on 12/19/24.
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

    func setDitTime(_ time: Double) {
        self.currentDitTime = time
    }

    func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        player.osc.amplitude = 0.0
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
        print("assembling tones,...")
        print("input = \(input)")
        var tones = [Tone]()
        
        let words = Morse.morseWords(from: input)
        let lastWordIndex = words.count - 1
        var unhandledCount = 0
        
        for (i,word) in words.enumerated() {
            print("word \(i) = \(word)")
            let lastCharIndex = word.count - 1
            
            for (j,char) in word.enumerated() {
                print("char \(j) \(char)")
                switch char {
                case ".":
                    print("dit")
                    tones.append( .init(.dit, ditTime: ditTime))
                    
                    if j != lastCharIndex {
                        print("adding infraspace")
                        tones.append(.init(.infraSpace, ditTime: ditTime))
                    }
                case "-":
                    print("dah")
                    tones.append(.init(.dah, ditTime: ditTime))
                    if j != lastCharIndex {
                        print("adding infraspace")
                        tones.append(.init(.infraSpace, ditTime: ditTime))
                    }
                default:
                    print("\(char) unhandled.")
                   
                    if unhandledCount % 3 == 0 {
                        print("found letterspaceß")
                        tones.append(.init(.letterSpace, ditTime: ditTime))
                    }else if unhandledCount % 7 == 0 {
                       print("found wordspace")
                    }
                    unhandledCount += 1
                    
                }
              
            }
            unhandledCount = 0
            print("wordspace")
            if i != lastWordIndex {
                print("addingWOrdspace")
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
        print("sequencing tones...")
        var sequence = [Conductor.SequencedTone]()
        
        let enums = input.enumerated()
        
        
        for (index, tone) in enums {
            if index == 0 {
                sequence.append(Conductor.SequencedTone(id:index,
                                                        tone: tone,
                                                        previous: nil,
                                                        next: input[index + 1]))
                
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
    
    /// Top level API to turn morse strings into played tones.
    /// - Parameter morse: The morse code string to play.
    /// - Parameter ditTime: The unit duration (in seconds) for a "dit". This parameter is now fully respected for all playback unit durations.
    public func sound(morse: String,
                      with ditTime: Double = 0.2)   {
        self.currentDitTime = ditTime
        let input = morse.trimmingCharacters(in: .whitespacesAndNewlines)
        let tones = self.sequencedTones(for: self.cleanedTones(for: assembledTones(for: input,
                                                                                   ditTime: ditTime)))
        
        Task { @MainActor in
            self.tones = tones
            self.playedDuration = 0
            self.totalDuration = await self.calculatedDuration(for: self.tones.map(\.tone))
        }
        
        let start = Date()
        
        self.playbackTask = Task {
            defer {
                Task { @MainActor in
                    self.isPlaying = false
                }
            }

            do {
                try self.player.engine.start()

                Task { @MainActor in
                    self.isPlaying = true
                    self.playedTones.removeAll()
                    self.unPlayedTones.removeAll()
                    self.unPlayedTones.append(contentsOf: tones)
                }

                for seq in tones {
                    if Task.isCancelled { break }

                    Task { @MainActor in
                        self.currentTone = seq
                        if seq.tone.amplitude == 0 {
                            self.isSounding = false
                        } else {
                            self.isSounding = true
                        }
                    }

                    let liveTone: Tone
                    if let symbol = Morse.Symbols(rawValue: seq.tone.morse) {
                        liveTone = Tone(symbol, ditTime: self.currentDitTime)
                    } else {
                        liveTone = seq.tone
                    }
                    try await self.player.play(tone: liveTone)
                    Task { @MainActor in
                        self.playedTones.append(seq)
                        self.unPlayedTones.removeAll(where: { $0.id == seq.id })
                    }
                }

                DispatchQueue.main.async {
                    let end = Date()
                    self.playedDuration = end.timeIntervalSince(start)
                }

            } catch is CancellationError {
                // stopped by user — defer handles isPlaying reset
            } catch {
                print("error \(error)")
            }
        }
    }
}
