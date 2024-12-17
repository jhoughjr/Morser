//
//  Player.swift
//  MorserX
//
//  Created by Jimmy Hough Jr on 12/16/24.
//


import Morse
import AudioKit
import AVFoundation

actor Conductor: ObservableObject {
    
    @MainActor @Published var isPlaying:Bool = false
    @MainActor @Published var playedTones:[SequencedTone] = []
    
    public struct SequencedTone {
        let id:Int
        let tone:Tone
        let previous:Tone?
        let next:Tone?
    }
    
    nonisolated let player:Player = Player()
    
    private func calculatedDuration(for tones:[Tone]) -> TimeInterval {
        let duration = tones.reduce(0) { $0 + $1.duration }
        return duration
    }
    
    private func assembledTones(for input: String, using timing: [String:Double] = Morse.Symbols.Timings()) -> [Tone] {
        var tones = [Tone]()
        let enumerated = input.enumerated()
        
        let dit = Morse.Symbols.ditTime()
        let dah = 3 * dit
        let lspace = dit
        let wspace = dah
        
        enumerated.forEach({ (index, char) in
            switch char {
            case ".":
                print("dit")
                tones.append(.init(duration: dit, amp: 1))
                //                    print("lspace")
                tones.append(.init(duration: lspace, amp: 0.0))
            case "-":
                print("dah")
                tones.append(.init(duration: dah, amp: 1.0))
                //                    print("lspace")
                tones.append(.init(duration: lspace, amp: 0.0))
                //
            case " ":
                print("wspace")
                tones.append(.init(duration: wspace, amp: 0.0))
                
            default:
                print("\(char) unhandled.")
                break
            }
        })
        return tones
        
    }
    
    public func sequencedTones(for input: [Tone]) -> [Conductor.SequencedTone] {
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
    
    public func sound(morse: String)   {
        let input = morse.trimmingCharacters(in: .whitespacesAndNewlines)
        let tones = sequencedTones(for: assembledTones(for: input))
        print("playing \(tones.count) tones.")
        print("should take \(calculatedDuration(for: tones.map(\.tone))) seconds.")
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
            }
            
            for seq in tones {
                await self.player.play(tone: seq.tone )
            }
            
            self.player.engine.stop()
            print("Engine stopped.")
            Task { @MainActor in
                self.isPlaying = false
            }
            DispatchQueue.main.async {
                let end = Date()
                print("\(end.timeIntervalSince(start)) seconds elapsed.")
                print("done playing \(input)")
            }
        }
    }
    
}

public class Player {
    
    nonisolated let engine = AudioEngine()
    nonisolated let osc = PlaygroundOscillator()
    
    init() {
        
        engine.output = osc
        print("Engine:\(engine.connectionTreeDescription)")
    }
    
    public func play(tone: Tone) async {
        
        self.osc.amplitude = tone.amplitude
        self.osc.start()
        await Task.sleep(seconds: tone.duration)
        self.osc.stop()

    }
}

