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

public struct Tone {
  
    var frequency:Float = 440
    var amplitude:Float = 1.0
    var duration:Double = 100
    var morse = ""
    
    var description: String {
        "\(duration) s \(frequency) Hz \(amplitude) Am"
    }
    
    init(_ symbol:Morse.Symbols,
         frequency:Float = 440) {
        switch symbol {
            
        case .dit:
            morse = "."
            self.duration = Morse.Symbols.ditTime()
            self.amplitude = 1.0
        case .dah:
            morse = "-"
            self.duration = Morse.Symbols.ditTime() * 3
            self.amplitude = 1.0
        case .infraSpace:
            morse = Morse.Symbols.infraSpace.rawValue
            self.duration = Morse.Symbols.ditTime()
            self.amplitude = 0.0
        case .letterSpace:
            morse = Morse.Symbols.letterSpace.rawValue
            self.duration = Morse.Symbols.ditTime() * 3
            self.amplitude = 0.0
        case .wordSpace:
            morse = Morse.Symbols.wordSpace.rawValue
            self.duration = Morse.Symbols.ditTime() * 7
            self.amplitude = 0.0
        }
    }
    
    @available(*, deprecated,
                renamed: "init(symbol:duration:)",
                message: "Use this instead") init(duration: Double, amp: Float = 1.0) {
        self.duration = duration
        self.amplitude = amp
    }
}
