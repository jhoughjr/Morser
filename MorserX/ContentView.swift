//
//  ContentView.swift
//  MorserX
//
//  Created by Jimmy Hough Jr on 12/13/24.
//

import SwiftUI
import Morse

struct Controllers {
    class TimingController: ObservableObject {
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
}

struct Views {
    
    struct MorseSymbolView: View {
        var symbol: Morse.Symbols
        
        var body: some View {
            switch symbol {
            case .dit:
                Text("dit")
            case .dah:
                Text("dah")
            case .infraSpace:
                Text("_")
            case .letterSpace:
                Text("___")
            case .wordSpace:
                Text("_______")
            }
        }
    }
    
    struct MorseFlasherView: View {
        enum FlashType {
            case foregrounfSymbol
            case background
        }
        
        @ObservedObject var conductor:Conductor
        @State var flashType:FlashType = .background
        
        var bgFlashView: some View {
            ZStack {
                if conductor.isSounding {
                    Color.red
                }else {
                    Color.gray
                }
                if let tone = conductor.currentTone?.tone {
                    
                    if let s = Morse.Symbols(rawValue: tone.morse) {
                        MorseSymbolView(symbol: s)
                            .font(.largeTitle)
                    }
                    
                }
            }
        }
        
        var symbolFlashView: some View {
            ZStack {
                Color.gray
                if conductor.isSounding {
                    if let tone = conductor.currentTone?.tone {
                        
                        if let s = Morse.Symbols(rawValue: tone.morse) {
                            MorseSymbolView(symbol: s)
                                .font(.largeTitle)
                                .foregroundStyle(Color.white)
                        }
                        
                    }
                }else {
                    if let tone = conductor.currentTone?.tone {
                        
                        if let s = Morse.Symbols(rawValue: tone.morse) {
                            MorseSymbolView(symbol: s)
                                .font(.largeTitle)
                                .foregroundStyle(Color.white)
                        }
                        
                    }
                }
                
            }
        }
        
        var body: some View {
            VStack {
                HStack {
                    Button {
                        self.flashType = .background
                    } label: {
                        Text("Flash Background")
                    }
                    Button {
                        self.flashType = .foregrounfSymbol
                    } label: {
                        Text("Flash Symbol")
                    }
                }
                
                switch flashType {
                case .foregrounfSymbol:
                    symbolFlashView
                case .background:
                    bgFlashView
                }
                
            }
        }
    }
}

class HoverWatcher: ObservableObject {
    @Published var hoveredTone: Conductor.SequencedTone? = nil
    
    public func watch(for tone: Conductor.SequencedTone) {
        self.hoveredTone = tone
    }
}

struct ContentView: View {
    
    @ObservedObject var morseController = Controllers.MorseController()
    @ObservedObject var conductor = Conductor()
    @ObservedObject var timingController = Controllers.TimingController()
    
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
    
    var legendView: some View {
        VStack {
            HStack {
                Text("Symbol Infraspace")
                   
                Text(".")
                    .foregroundStyle(.gray)
            }
            HStack {
                Text("Letter Interspace")
                Text("...")
                    .foregroundStyle(.red)
            }
            HStack {
                Text("Word Interspace")
                Text("...")
                    .foregroundStyle(.blue)
                
            }
        }
    }
    
    @State private var scrollPosition: Int? = 0

    var scrollingMorseView: some View {
        
        ScrollView(.horizontal) {
            
            HStack {
                Spacer()
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
                        
                        if t.tone.morse == Morse.Symbols.wordSpace.rawValue {
                            Text(".......")
                                .font(.title)
                                .foregroundStyle(t.id == conductor.currentTone?.id ? Color.green : Color.blue)
                        }
                        if t.tone.morse == Morse.Symbols.letterSpace.rawValue {
                            Text("...")
                                .font(.title)
                                .foregroundStyle(t.id == conductor.currentTone?.id ? Color.green : Color.red)
                        }
                        if t.tone.morse == Morse.Symbols.infraSpace.rawValue {
                            Text(".")
                                .font(.title)
                                .foregroundStyle(t.id == conductor.currentTone?.id ? Color.green : Color.gray)
                        }
                        Spacer()
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
            }
            
        }
        .scrollPosition(id: $scrollPosition)

    }
    
    var playerView: some View {
        VStack {
            Button {
                self.scrollPosition = 0
                Task {
                    await conductor.sound(morse: morseController.morseCode)
                }
                
            } label: {
                Text("Play")
            }
            .disabled(conductor.isPlaying)
            
            playingInfo
            scrollingMorseView
            legendView
            Spacer()
        }
    }
    
    var body: some View {
        
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
         
            inputView
            playerView
            Views.MorseFlasherView(conductor: conductor)
                .onChange(of: conductor.currentTone) { oldValue, newValue in
                    scrollPosition = scrollPosition == nil ? 0 : (scrollPosition! + 1)
                }
         
        }
        .padding()
    }
}
