//
//  Player.swift
//  MorserX
//
//  Created by Jimmy Hough Jr on 12/16/24.
//

import AudioKit

public class Player {
    
    nonisolated let engine = AudioEngine()
    nonisolated let osc = PlaygroundOscillator(waveform: Table(.sawtooth))
    
    init() {
        
        engine.output = osc
        print("Engine:\(engine.connectionTreeDescription)")
    }
    
    public func play(tone: Tone) async {

        self.osc.amplitude = tone.amplitude
        self.osc.start()
        
        do {
            try await Task.sleep(for: .milliseconds( tone.duration * 1000 ))
            self.osc.amplitude = 0.0
//            self.osc.stop()

        }
        catch {
            print("\(error)")
//            self.osc.stop()

        }
        

    }
}

