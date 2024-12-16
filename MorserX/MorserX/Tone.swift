//
//  Tone.swift
//  MorserX
//
//  Created by Jimmy Hough Jr on 12/13/24.
//

/*
 See the LICENSE.txt file for this sample’s licensing information.
 
 Abstract:
 The main source file for SignalGenerator.
 */

import Foundation
import Morse
import AudioKit
import AVFAudio

class Tone {
    
    struct SequencedTone {
        let id:Int
        let tone:Tone
        let previous:Tone?
        let next:Tone?
    }
    
    struct Signals {
        
        static let twoPi = 2 * Float.pi

        static let sine = { (phase: Float) -> Float in
            return sin(phase)
        }
        
        static let whiteNoise = { (phase: Float) -> Float in
            return ((Float(arc4random_uniform(UINT32_MAX)) / Float(UINT32_MAX)) * 2 - 1)
        }
        
        static let sawtoothUp = { (phase: Float) -> Float in
            return 1.0 - 2.0 * (phase * (1.0 / twoPi))
        }
        
        static let sawtoothDown = { (phase: Float) -> Float in
            return (2.0 * (phase * (1.0 / twoPi))) - 1.0
        }
        
        static let square = { (phase: Float) -> Float in
            if phase <= Float.pi {
                return 1.0
            } else {
                return -1.0
            }
        }
        
        static let triangle = { (phase: Float) -> Float in
            var value = (2.0 * (phase * (1.0 / twoPi))) - 1.0
            if value < 0.0 {
                value = -value
            }
            return 2.0 * (value - 0.5)
        }
    }
    
    public actor Player: ObservableObject {
        var playedTones: [Tone] = []
        var isPlaying = false
        
        let engine = AudioEngine()
        let osc = PlaygroundOscillator()
        
        init() {
            engine.output = osc
        }
        
        private func configureEngine(for tone: Tone) {
            osc.amplitude = tone.amplitude
        }
        
        private func play(tone: Tone) -> Bool {
            if isPlaying { return false }
            
            isPlaying = true
            
            print("Playing \(tone.description)")
            configureEngine(for: tone)
            osc.start()
            CFRunLoopRunInMode(.defaultMode, CFTimeInterval(tone.duration), false)
            osc.stop()
            isPlaying = false
            return true
        }
        
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
        
        private func sequencedTones(for input: [Tone]) -> [SequencedTone] {
            var sequence = [SequencedTone]()
            
            let enums = input.enumerated()
            
            for (index, tone) in enums {
                if index == 0 {
                    sequence.append(SequencedTone(id:index,
                                                  tone: tone,
                                                  previous: nil,
                                                  next: input[index + 1]))
                    
                }else if index < input.count - 1 {
                    
                    sequence.append(SequencedTone(id:index,
                                                  tone: tone,
                                                  previous: input[index - 1],
                                                  next: input[index + 1]))
                    
                }else if index == input.count - 1 {
                    sequence.append(SequencedTone(id:index,
                                                  tone: tone,
                                                  previous: input[index - 1],
                                                  next: nil))
                }
                
            }
            return sequence
        }
        
        public func sound(morse: String) async  {
           
                let input = morse.trimmingCharacters(in: .whitespacesAndNewlines)
                let tones = self.sequencedTones(for: self.assembledTones(for: input))
                print("playing \(tones)")
                print("should take \(calculatedDuration(for: tones.map(\.tone))) seconds")
            
                let start = Date()
                try? self.engine.start()
            
                tones.forEach { tone in
                    if self.play(tone: tone.tone ) {
                        self.playedTones.append(tone.tone)
                    }else {
                        print("still playing tone \(tone)")
                    }
                }
                self.engine.stop()
                let end = Date()
                print("\(end.timeIntervalSince(start)) seconds elapsed.")
                print("done playing \(input)")
            }
                      
    }
    
    var frequency:Float = 440
    var amplitude:Float = 1.0
    var duration:Double = 0.1
    
    var description: String {
        "\(duration) \(frequency) \(amplitude)"
    }
        
    init(duration: Double, amp: Float = 1.0) {
        self.duration = duration
        self.amplitude = amp
    }
}
