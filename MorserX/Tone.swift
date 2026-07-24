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

    /// Pitch for this element, or nil to use the renderer's sidetone.
    ///
    /// This replaces a `frequency` field that every initialiser dutifully set
    /// and the renderer then ignored — it computed one phase step for the whole
    /// transmission. A field that nothing reads is worse than no field: it reads
    /// like a supported feature.
    var pitch: Float?
    var amplitude:Float = 1.0
    var duration:Double = 100
    var morse = ""
    
    var description: String {
        "\(duration) s \(pitch.map { "\($0) Hz" } ?? "sidetone") \(amplitude) Am"
    }
    
    /// Preferred initializer for playback: uses explicit ditTime duration for accurate timing
    init(_ symbol: Morse.Symbols, ditTime: Double, pitch: Float? = nil) {
        switch symbol {
            
        case .dit:
            morse = "."
            self.duration = ditTime
            self.amplitude = 1.0
        case .dah:
            morse = "-"
            self.duration = ditTime * 3
            self.amplitude = 1.0
        case .infraSpace:
            morse = Morse.Symbols.infraSpace.rawValue
            self.duration = ditTime
            self.amplitude = 0.0
        case .letterSpace:
            morse = Morse.Symbols.letterSpace.rawValue
            self.duration = ditTime * 3
            self.amplitude = 0.0
        case .wordSpace:
            morse = Morse.Symbols.wordSpace.rawValue
            self.duration = ditTime * 7
            self.amplitude = 0.0
        }
        self.pitch = pitch
    }
    
    /// Deprecated initializer kept for compatibility. Use the timing-aware init for playback.
    init(_ symbol: Morse.Symbols,
         pitch: Float? = nil) {
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
        self.pitch = pitch
    }
}

