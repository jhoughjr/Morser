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
    
    public class Player {
        var isPlaying = false
        let engine = AudioEngine()
        let osc = PlaygroundOscillator()
        
        init() {
            engine.output = osc
        }
        
        private func configureEngine(for tone: Tone) {
            osc.amplitude = tone.amplitude
        }
        
        private func play(tone: Tone) {
            isPlaying = true
            print("Playing \(tone.description)")
            configureEngine(for: tone)
            osc.start()
            CFRunLoopRunInMode(.defaultMode, CFTimeInterval(tone.duration), false)
            osc.stop()
            isPlaying = false
        }
        
        private func assembledTones(for input: String) -> [Tone] {
            var tones = [Tone]()
            let enumerated = input.enumerated()
            let dit = Float(Morse.Symbols.ditTime())
            let dah = Float(3 * dit)
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
        
        public func sound(morse: String) {
           
                let input = morse.trimmingCharacters(in: .whitespacesAndNewlines)
                let tones = self.assembledTones(for: input)
                print("playing \(tones)")
                try? self.engine.start()
                tones.enumerated().forEach { t in
                    self.play(tone: t.element)
                }
                self.engine.stop()
                print("done playing \(input)")
            }
                      
    }
    
    let frequency:Float = 440
    var amplitude:Float = 1.0
    var duration:Float = 0.1
    
    var description: String {
        "\(duration) \(frequency) \(amplitude)"
    }
        
    init(duration: Float, amp: Float = 1.0) {
        self.duration = duration
        self.amplitude = amp
    }
}
