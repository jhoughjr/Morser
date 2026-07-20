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
    
    public func play(tone: Tone) async throws {
        // Always start the oscillator so it's ready for audio output.
        osc.amplitude = 0.0
        osc.start()

        // Silent tones (spaces) skip the ramp — just wait out the duration.
        guard tone.amplitude > 0 else {
            try await Task.sleep(for: .seconds(tone.duration))
            return
        }

        // Silence on completion or cancellation.
        defer { osc.amplitude = 0.0 }

        // Fade scales with tone duration so dit/dah ratio is preserved at all speeds.
        let fadeDuration = min(0.008, tone.duration * 0.15)
        let fadeSteps = max(2, Int(fadeDuration * 1000))
        let stepDuration = fadeDuration / Double(fadeSteps)

        func rampAmplitude(from start: Float, to end: Float) async throws {
            let delta = (end - start) / Float(fadeSteps)
            for i in 1...fadeSteps {
                osc.amplitude = start + delta * Float(i)
                try await Task.sleep(for: .seconds(stepDuration))
            }
        }

        try await rampAmplitude(from: 0.0, to: tone.amplitude)
        let sustainDuration = max(0.0, tone.duration - 2 * fadeDuration)
        try await Task.sleep(for: .seconds(sustainDuration))
        try await rampAmplitude(from: tone.amplitude, to: 0.0)
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
                try? await self.play(tone: Tone(.dit, ditTime: value))
            }
            let actual = Date().timeIntervalSince(start)
            results.append((id, value, expected, actual))
        }
        return results
    }
}
