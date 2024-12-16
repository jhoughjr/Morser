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

public struct Tone {
    
    var frequency:Float = 440
    var amplitude:Float = 1.0
    var duration:Double = 100
    
    var description: String {
        "\(duration) s \(frequency) Hz \(amplitude) Am"
    }
        
    init(duration: Double, amp: Float = 1.0) {
        self.duration = duration
        self.amplitude = amp
    }
}
