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
    @Published var morseText: String = "hello world"
    @Published var morseCode: String = ""

    public func convertToMorse() {
        morseCode = Morse.morse(from: self.morseText)
    }
    
    public func convertToText() {
        morseText = Morse.latin(from: self.morseCode)
    }
    
}

class HoverWatcher: ObservableObject {
    @Published var hoveredTone: Conductor.SequencedTone? = nil
    
    public func watch(for tone: Conductor.SequencedTone) {
        self.hoveredTone = tone
    }
}

struct ContentView: View {
    @ObservedObject var morseController: MorseController = MorseController()
    @ObservedObject var conductor = Conductor()
    @ObservedObject var timingController = TimingController()
    @ObservedObject var hoverWatcher: HoverWatcher = HoverWatcher()
    
    var inputView: some View {
        VStack {
            textInView
            morseInView.disabled(true)
        }
    }
    
    var textInView: some View {
        HStack {
            TextField("morseText", text: $morseController.morseText,
                      prompt: Text("Hello, world!"))
            
            Button {
                morseController.convertToMorse()
            } label: {
                Text("to Morse")
            }
            
        }
    }
    var morseInView: some View {
        HStack {
            TextField("morseCode", text: $morseController.morseCode)
            Button {
                morseController.convertToText()
            } label: {
                Text("to text")
            }
        }
    }
    var playingInfo: some View {
        VStack {
            if conductor.playedTones.isNotEmpty {
                Text("Estimated Duration: \(conductor.totalDuration)")
                Text("Played \(conductor.playedTones.count) of \(conductor.tones.count)")
                Text("Measured Duration: \(conductor.playedDuration)")
            }
        }
    }
    
    var scrollingMorseView: some View {
        ScrollView {
            HStack {
                ForEach(conductor.tones,
                        id: \.id) { t in
                    
                    VStack {
                        if hoverWatcher.hoveredTone?.id == t.id {
                            Text(t.tone.duration, format: .number)
                                .font(.caption)
                                .fontWeight(.ultraLight)
                        }
                        
                        if conductor.currentTone?.id == t.id {
                            Text("\(t.tone.morse)")
                            .font(.title)
                            .foregroundStyle(Color.green)
                        }else
                        {
                            Text("\(t.tone.morse)")
                                .font(.title)
                                .foregroundStyle(Color.white)
                        }
                        
                        if t.tone.morse == Morse.Symbols.wordSpace.rawValue ||
                            t.tone.morse == Morse.Symbols.letterSpace.rawValue ||
                            t.tone.morse == Morse.Symbols.infraSpace.rawValue {
                            Text("_")
                                .font(.title)
                                .foregroundStyle(Color.red)
                        }
            
                    }
                    .onContinuousHover(perform: { phase in
                        switch phase {
                            
                        case .active:
                            hoverWatcher.hoveredTone = t
                        case .ended:
                            hoverWatcher.hoveredTone = nil
                        }
                    })
                }
                Spacer()
            }
        }
    }
    
    var playerView: some View {
        VStack {
            Button {
                Task {
                    await conductor.sound(morse: morseController.morseCode)
                }
                
            } label: {
                Text("Play")
            }
            .disabled(conductor.isPlaying)
            
            playingInfo
            
            scrollingMorseView
        }
    }
    
    var body: some View {
        
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
         
            inputView
            playerView
         
        }
        .padding()
    }
}

