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
    @MainActor @Published var unPlayedTones:[SequencedTone] = []
    @MainActor @Published var tones:[SequencedTone] = []
    @MainActor @Published var totalDuration:TimeInterval = 0.0
    @MainActor @Published var playedDuration:TimeInterval = 0.0

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
    
    private func assembledTones(for input: String,
                                using ditTime: Double = 0.2) -> [Tone] {
        print("assembling with ditTime \(ditTime)")
        var tones = [Tone]()
        let enumerated = input.enumerated()
        
        let dit = ditTime
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
    
    public func sound(morse: String, with ditTime: Double = 0.2)   {
        print("sound with \(ditTime) dit time.")
        let input = morse.trimmingCharacters(in: .whitespacesAndNewlines)
        let tones = self.sequencedTones(for: assembledTones(for: input, using: ditTime))
        
        Task { @MainActor in
            self.tones = await self.sequencedTones(for: assembledTones(for: input, using: ditTime))
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
                await self.player.play(tone: seq.tone )
                Task { @MainActor in
                    self.playedTones.append(seq)
                    self.unPlayedTones.removeAll(where: { $0.id == seq.id })
                }
            }
            
            self.player.engine.stop()
            print("Engine stopped.")
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
        print("       playing for \(tone.duration)")
        await Task.sleep(seconds: tone.duration)
        self.osc.stop()

    }
}

