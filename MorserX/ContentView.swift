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
        @Published var ditTime:Double = 0.1
        @Published var dahTime:Double = 3 * 0.2
    }

    class MorseController: ObservableObject {
        /// Encoding is a property of the text, not something a view has to remember
        /// to trigger. It used to be driven by the TextField's `onChange`, which meant
        /// the launch value was never encoded — the field read "hello world" while
        /// `morseCode` was still empty, so Play had nothing to sequence.
        @Published var morseText: String = "hello world" {
            didSet { convertToMorse() }
        }
        @Published var morseCode: String = ""
        /// One per character group in `morseCode`, in order.
        @Published var tokens: [Morse.Token] = []
        /// Characters that can't be sent. The encoder used to drop these without
        /// a word, so the field showed text the audio never transmitted.
        @Published var skipped: [Character] = []

        init() {
            convertToMorse()
        }

        public func convertToMorse() {
            let encoded = Morse.encode(morseText)
            morseCode = encoded.morse
            tokens = encoded.tokens
            skipped = encoded.skipped
        }

    }
}

struct Views {

    /// The lamp.
    ///
    /// This panel used to be a second copy of the strip, drawn as a row of small
    /// glyphs in a large dark field — mostly empty space with a few marks in it,
    /// which is the worst of both: too sparse to read as a picture, too small to
    /// read as text. It now does the one thing the strip can't, which is tell you
    /// what is being sent *right now*, big enough to read across a room.
    struct MorseFlasherView: View {
        @ObservedObject var conductor: Conductor
        let labels: [String]

        var body: some View {
            let model = StripLayout.build(tones: conductor.tones, labels: labels)
            let currentID = conductor.currentTone?.id ?? -1
            let group = model.groups.first { $0.ids.contains(currentID) }

            ZStack {
                Color(white: 0.08)

                if conductor.tones.isEmpty {
                    Text("Type text above to see morse here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(spacing: 12) {
                        lamp
                        Text(group?.label ?? " ")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .animation(nil, value: currentID)
                        symbolRow(for: group, currentID: currentID)
                    }
                }
            }
        }

        /// Lit while the key is down, so the rhythm is visible as well as audible.
        private var lamp: some View {
            Circle()
                .fill(conductor.isSounding ? Color.green : Color.white.opacity(0.10))
                .frame(width: 22, height: 22)
                .shadow(color: conductor.isSounding ? .green.opacity(0.9) : .clear, radius: 12)
                .shadow(color: conductor.isSounding ? .green.opacity(0.5) : .clear, radius: 28)
                .animation(.easeOut(duration: 0.05), value: conductor.isSounding)
        }

        /// The character's own symbols, with the one being sounded picked out —
        /// which is where you are inside the letter, not just which letter it is.
        @ViewBuilder
        private func symbolRow(for group: StripLayout.Group?, currentID: Int) -> some View {
            if let group {
                HStack(spacing: 8) {
                    ForEach(group.ids, id: \.self) { id in
                        let tone = conductor.tones.first { $0.id == id }?.tone
                        let isDah = tone?.morse == Morse.Symbols.dah.rawValue
                        RoundedRectangle(cornerRadius: 2)
                            .fill(id == currentID ? Color.green : Color.white.opacity(0.35))
                            .frame(width: isDah ? 30 : 10, height: 8)
                    }
                }
                .frame(height: 10)
            } else {
                Color.clear.frame(height: 10)
            }
        }
    }
}

struct ContentView: View {

    // These are owned by the view, not handed to it — @ObservedObject on an inline
    // initializer makes the object a fresh instance every time the struct is rebuilt.
    @StateObject private var morseController = Controllers.MorseController()
    @StateObject private var conductor = Conductor()
    @StateObject private var timingController = Controllers.TimingController()

    @State private var hoveredGroup: Int?
    @State private var isShowingSettings = false
    @State private var isShowingKeyer = false
    @State private var isShowingPractice = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            inputSection
            Divider()
            Views.MorseFlasherView(conductor: conductor, labels: promptLabels)
                .frame(minHeight: 120, maxHeight: 180)
            Divider()
            morseScrollStrip
            Divider()
            controlsSection
        }
        .task {
            // The launch text is already encoded; sequence it so the strip has
            // something in it before the user touches anything.
            await conductor.load(morse: morseController.morseCode,
                                 with: timingController.ditTime)
        }
        .onChange(of: morseController.morseCode) { _, code in
            Task { await conductor.load(morse: code, with: timingController.ditTime) }
        }
        .onChange(of: timingController.ditTime) { _, newValue in
            Task { await conductor.setDitTime(newValue) }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Text("MorserX")
                .font(.headline)
            Spacer()
            Button {
                isShowingPractice = true
            } label: {
                Image(systemName: "graduationcap")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("practiceButton")
            .help("Practice copying")
            .sheet(isPresented: $isShowingPractice) {
                // Practice borrows the audio engine but not the strip; still, a
                // half-finished send leaves the engine stopped mid-sequence.
                Task { await conductor.load(morse: morseController.morseCode,
                                            with: timingController.ditTime) }
            } content: {
                PracticeView(conductor: conductor)
            }

            Button {
                isShowingKeyer = true
            } label: {
                Image(systemName: "keyboard")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isShowingKeyer) {
                KeyerView(player: conductor.player, timingController: timingController)
                    .frame(minWidth: 320, minHeight: 520)
            }

            Button {
                isShowingSettings = true
            } label: {
                Image(systemName: "gear")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $isShowingSettings) {
                TimingDiagnosticsView(player: conductor.player)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Enter text...", text: $morseController.morseText,
                      prompt: Text("Hello, world!"))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("inputField")

            if !morseController.morseCode.isEmpty {
                Text(morseController.morseCode)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Type to generate morse code")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if !morseController.skipped.isEmpty {
                Label("Can't send \(morseController.skipped.map(String.init).joined(separator: " "))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
    }

    // MARK: - Morse strip

    private var morseScrollStrip: some View {
        MorseStripView(tones: conductor.tones,
                       currentID: conductor.currentTone?.id ?? -1,
                       labels: promptLabels,
                       hoveredGroup: $hoveredGroup)
    }

    /// What each group under the strip spells.
    ///
    /// This used to re-derive the encoder's skipping rule by filtering the text
    /// the same way, which only worked for as long as the two agreed. The encoder
    /// now reports the tokens it actually sent, so there is nothing to keep in
    /// step.
    private var promptLabels: [String] {
        morseController.tokens.map(\.text)
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 10) {
            Slider(value: $timingController.ditTime, in: 0.01...0.1, step: 0.001) {
                EmptyView()
            } minimumValueLabel: {
                Text("Fast").font(.caption2).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("Slow").font(.caption2).foregroundStyle(.secondary)
            }

            HStack {
                Text("Dit: \(timingController.ditTime, specifier: "%.3f") s")
                Spacer()
                // Dits-per-second was labelled "bps", which is neither. Speed in
                // morse is words per minute against the standard word PARIS.
                Text("\(Int(Morse.Timing.wpm(ditTime: timingController.ditTime).rounded())) wpm")
                    .fontWeight(.medium)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Button {
                if conductor.isPlaying {
                    Task { await conductor.stop() }
                } else {
                    Task {
                        await conductor.sound(morse: morseController.morseCode,
                                              with: timingController.ditTime)
                    }
                }
            } label: {
                Text(conductor.isPlaying ? "Stop" : "Play")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(conductor.isPlaying ? .red : .accentColor)
            .keyboardShortcut(.return, modifiers: [])
        }
        .padding()
    }
}
