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
    
    private func calculatedDuration(for tones:[Tone]) -> TimeInterval {
        let duration = tones.reduce(0) { $0 + $1.duration }
        return duration
    }
    
    private func assembledTones(for input: String) -> [Tone] {
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
                    tones.append( .init(.dit))
                    
                    if j != lastCharIndex {
                        print("adding infraspace")
                        tones.append(.init(.infraSpace))
                    }
                case "-":
                    print("dah")
                    tones.append(.init(.dah))
                    if j != lastCharIndex {
                        print("adding infraspace")
                        tones.append(.init(.infraSpace))
                    }
                default:
                    print("\(char) unhandled.")
                   
                    if unhandledCount % 3 == 0 {
                        print("found letterspaceß")
                        tones.append(.init(.letterSpace))
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
                tones.append(.init(.wordSpace))
            }
        }
        return tones
        
    }
    
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
        
        print("reurning \(filteredInput.count) tones")
        return filteredInput
    }
    
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
    
    public func sound(morse: String, with ditTime: Double = 0.2)   {
        print("sound with \(ditTime) dit time.")
        let input = morse.trimmingCharacters(in: .whitespacesAndNewlines)
        let tones = self.sequencedTones(for: self.cleanedTones(for: assembledTones(for: input)))
        
        Task { @MainActor in
            self.tones = tones
            self.playedDuration = 0
            self.totalDuration = await self.calculatedDuration(for: self.tones.map(\.tone))
            print("playing \(self.tones.count) tones.")
            print("should take \(await self.calculatedDuration(for: self.tones.map(\.tone))) seconds.")
        }
        
        
        let start = Date()
        
        Task {
            do {
                print("Starting AudioEngine...")
                try  self.player.engine.start()
                print("    Started AudioEngine.")
                
            }
            catch {
                print("error \(error)")
            }
            print("Playing tones...")
            Task { @MainActor in
                self.isPlaying = true
                self.playedTones.removeAll()
                self.unPlayedTones.removeAll()
                self.unPlayedTones.append(contentsOf: tones)
            }
            
            for seq in tones {
                
                Task { @MainActor in
                    self.currentTone = seq
                    if seq.tone.amplitude == 0 {
                        isSounding = false
                    }else {
                        isSounding = true
                    }
                }
                
                await self.player.play(tone: seq.tone )
                Task { @MainActor in
                    self.playedTones.append(seq)
                    self.unPlayedTones.removeAll(where: { $0.id == seq.id })
                }
            }
            
            self.player.engine.stop()
            print("Audio Engine stopped.")
            Task { @MainActor in
                self.isPlaying = false
            }
            
            DispatchQueue.main.async {
                let end = Date()
                self.playedDuration = end.timeIntervalSince(start)
                
                print("\(end.timeIntervalSince(start)) seconds elapsed.")
                print("done playing \(input)")
            }
        }
    }
}
