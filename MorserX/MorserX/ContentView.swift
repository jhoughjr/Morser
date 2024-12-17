//
//  ContentView.swift
//  MorserX
//
//  Created by Jimmy Hough Jr on 12/13/24.
//

import SwiftUI
import Morse

class TimingController:ObservableObject {
    @Published var ditTime:Double = 0.2
    @Published var dahTime:Double = 3 * 0.2

}

class MorseController: ObservableObject {
    @Published var morseText: String = ""
    @Published var morseCode: String = ""

    public func convertToMorse() {
        morseCode = Morse.morse(from: self.morseText)
    }
    
    public func convertToText() {
        morseText = Morse.latin(from: self.morseCode)
    }
    
}

struct ContentView: View {
    @ObservedObject var morseController: MorseController = MorseController()
    @ObservedObject var conductor = Conductor()
    @ObservedObject var timingController = TimingController()
    
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            HStack {
                Text(". time")
                TextField("ditTime", value: $timingController.ditTime, format: .number)
            }
            
            HStack {
                TextField("morseText", text: $morseController.morseText,
                          prompt: Text("Hello, world!"))
                Button {
                    morseController.convertToMorse()
                } label: {
                    Text("to Morse")
                }
                
            }
            
            HStack {
                TextField("morseCode", text: $morseController.morseCode)
                Button {
                    morseController.convertToText()
                } label: {
                    Text("to text")
                }
            }
            
            HStack {
                
                Button {
                    Task {
                        await conductor.sound(morse: morseController.morseCode,
                                              with: timingController.ditTime)
                    }
                    
                } label: {
                    Text("Play Test")
                }
                .disabled(conductor.isPlaying)
            }
           
            if conductor.playedTones.isNotEmpty {
                Text("Estimated Duration: \(conductor.totalDuration)")
                Text("Played \(conductor.playedTones.count) of \(conductor.tones.count)")
                Text("Measured Duration: \(conductor.playedDuration)")
            }
            VStack {
                List {
                    ForEach(conductor.tones,
                            id: \.id) { tone in
                        Text("\(tone)")
                    }
                }
            }

        }
        .padding()
    }
}

