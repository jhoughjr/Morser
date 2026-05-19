//
//  Player.swift
//  MorserX
//
//  Created by Jimmy Hough Jr on 12/16/24.
//

import AudioKit
import SwiftUI

public class Player: ObservableObject {
    
    nonisolated let engine = AudioEngine()
    nonisolated let osc = PlaygroundOscillator(waveform: Table(.sawtooth))
    
    func setManualRenderingBufferSize(bytes:UInt32) {
    
    }
    init() {
        
        engine.output = osc
        print("Engine:\(engine.connectionTreeDescription)")
        do {
            try engine.start()
        } catch {
            print("Failed to start engine: \(error)")
        }
    }
    
    public func play(tone: Tone) async {
        let fadeDuration = 0.01 // seconds (10ms)
        let fadeSteps = 20
        let stepDuration = fadeDuration / Double(fadeSteps)
        
        func rampAmplitude(from start: Float, to end: Float) async {
            let delta = (end - start) / Float(fadeSteps)
            for i in 0...fadeSteps {
                osc.amplitude = start + delta * Float(i)
                try? await Task.sleep(for: .seconds(stepDuration))
            }
        }
        
        osc.amplitude = 0.0
        osc.start()
        
        await rampAmplitude(from: 0.0, to: tone.amplitude)
        let playDuration = max(0.0, Double(tone.duration) - 2 * fadeDuration)
        try? await Task.sleep(for: .seconds(playDuration))
        await rampAmplitude(from: tone.amplitude, to: 0.0)
        osc.amplitude = 0.0
    }
    
    // Add a diagnostic function to Player to test timing accuracy.
    // It sweeps a range of ditTime values, plays 10 dits each, and logs expected/actual durations.
    // Returns a list of (ditTime, expected, actual) tuples for display or analysis.
    //
    // API:
    //   public func diagnoseTiming(sweep: [Double]) async -> [(ditTime: Double, expected: Double, actual: Double)]
    //
    // Usage example:
    //   let results = await player.diagnoseTiming(sweep: stride(from: 0.005, through: 0.1, by: 0.005).map { $0 })
    
    public func diagnoseTiming(sweep: [Double]) async -> [(id:Int,ditTime: Double, expected: Double, actual: Double)] {
        var results: [(Int,Double, Double, Double)] = []
        for value in sweep {
            let id = Int(value * 1000)
            let count = 10
            let expected = Double(count) * value
            let start = Date()
            for _ in 0..<count {
                await self.play(tone: Tone(.dit, ditTime: value))
            }
            let actual = Date().timeIntervalSince(start)
            results.append((id, value, expected, actual))
        }
        return results
    }
}
