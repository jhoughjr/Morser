//
//  KeyerView.swift
//  MorserX
//

import SwiftUI
import AudioKit

// MARK: - Keyer

@MainActor
class Keyer: ObservableObject {
    @Published var currentChar: String = ""
    @Published var history: [(id: Int, morse: String, letter: String)] = []
    @Published var decodedText: String = ""
    @Published var isDitActive = false
    @Published var isDahActive = false

    var ditTime: Double = 0.1
    nonisolated let player = Player()

    private var ditTask: Task<Void, Never>?
    private var spaceTask: Task<Void, Never>?
    private var charId = 0

    // MARK: - Dit paddle — auto-streams dits while held

    func ditDown() {
        guard !isDitActive else { return }
        isDitActive = true
        spaceTask?.cancel()
        ditTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.player.osc.amplitude = 1.0
                self.player.osc.start()
                do { try await Task.sleep(for: .seconds(self.ditTime)) } catch { break }
                self.player.osc.amplitude = 0.0
                self.currentChar += "."
                do { try await Task.sleep(for: .seconds(self.ditTime)) } catch { break }
            }
        }
    }

    func ditUp() {
        guard isDitActive else { return }
        isDitActive = false
        ditTask?.cancel()
        ditTask = nil
        player.osc.amplitude = 0.0
        scheduleSpacing()
    }

    // MARK: - Dah paddle — audio plays while held, symbol appended on release

    func dahDown() {
        guard !isDahActive else { return }
        isDahActive = true
        spaceTask?.cancel()
        player.osc.amplitude = 1.0
        player.osc.start()
    }

    func dahUp() {
        guard isDahActive else { return }
        isDahActive = false
        player.osc.amplitude = 0.0
        currentChar += "-"
        scheduleSpacing()
    }

    // MARK: - Auto letter / word spacing

    private func scheduleSpacing() {
        spaceTask = Task { [weak self] in
            guard let self else { return }
            do {
                // wait 3.5 dits → commit the current character
                try await Task.sleep(for: .seconds(self.ditTime * 3.5))
                self.commitChar()
                // wait another 4 dits → insert word space
                try await Task.sleep(for: .seconds(self.ditTime * 4.0))
                if !self.decodedText.isEmpty && !self.decodedText.hasSuffix(" ") {
                    self.decodedText += " "
                }
            } catch { /* cancelled by next keypress */ }
        }
    }

    private func commitChar() {
        let morse = currentChar
        guard !morse.isEmpty else { return }
        let letter = morseToLetter(morse) ?? "?"
        charId += 1
        history.append((id: charId, morse: morse, letter: letter))
        decodedText += letter
        currentChar = ""
    }

    private func morseToLetter(_ m: String) -> String? {
        [
            ".-":"A",  "-...":"B", "-.-.":"C", "-..":"D",  ".":"E",
            "..-.":"F","--.":"G",  "....":"H", "..":"I",   ".---":"J",
            "-.-":"K", ".-..":"L", "--":"M",   "-.":"N",   "---":"O",
            ".--.":"P","--.-":"Q", ".-.":"R",  "...":"S",  "-":"T",
            "..-":"U", "...-":"V", ".--":"W",  "-..-":"X", "-.--":"Y",
            "--..":"Z",
            "-----":"0",".----":"1","..---":"2","...--":"3","....-":"4",
            ".....":"5","-....":"6","--...":"7","---..":"8","----.":"9",
            ".-.-.-":".",  "--..--":",", "..--..":"?", ".----.":"'",
            "-.-.--":"!",  "-..-.":"/",  "-.--." :"(",  "-.--.-":")",
            ".-...":"&",   "---...":":", "-.-.-.":";",  "-...-":"=",
            ".-.-.":"+" ,  "-....-":"-", "..--.-":"_",  ".-..-.":"\"",
            "...-..-":"$", ".--.-.":"@"
        ][m]
    }

    func clear() {
        ditTask?.cancel()
        spaceTask?.cancel()
        ditTask = nil
        spaceTask = nil
        currentChar = ""
        history = []
        decodedText = ""
        player.osc.amplitude = 0.0
        isDitActive = false
        isDahActive = false
    }
}

// MARK: - Paddle Button

struct PaddleButton: View {
    let label: String
    let sublabel: String
    let color: Color
    let isActive: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(isActive ? color : color.opacity(0.1))
                .shadow(color: isActive ? color.opacity(0.7) : .clear, radius: 18)
                .animation(.easeInOut(duration: 0.04), value: isActive)

            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .foregroundStyle(isActive ? .white : color)
                    .shadow(color: isActive ? color.opacity(0.9) : .clear, radius: 6)
                    .shadow(color: isActive ? color.opacity(0.5) : .clear, radius: 18)
                    .animation(.easeInOut(duration: 0.04), value: isActive)
                Text(sublabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(isActive ? .white.opacity(0.85) : .secondary)
            }
        }
        .frame(height: 130)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPressing { isPressing = true; onPress() }
                }
                .onEnded { _ in
                    if isPressing { isPressing = false; onRelease() }
                }
        )
    }
}

// MARK: - Keyer View

struct KeyerView: View {
    @StateObject private var keyer = Keyer()
    @ObservedObject var timingController: Controllers.TimingController
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 20) {
            Text("Doodlebug Keyer")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top, 8)

            outputDisplay

            HStack(spacing: 16) {
                PaddleButton(
                    label: ".", sublabel: "Dit  · Z (hold)",
                    color: .blue, isActive: keyer.isDitActive,
                    onPress: {
                        keyer.ditTime = timingController.ditTime
                        keyer.ditDown()
                    },
                    onRelease: keyer.ditUp
                )
                PaddleButton(
                    label: "—", sublabel: "Dah  · X",
                    color: .orange, isActive: keyer.isDahActive,
                    onPress: {
                        keyer.ditTime = timingController.ditTime
                        keyer.dahDown()
                    },
                    onRelease: keyer.dahUp
                )
            }

            Button("Clear") { keyer.clear() }
                .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
        .onChange(of: timingController.ditTime) { _, v in keyer.ditTime = v }
        .onAppear {
            keyer.ditTime = timingController.ditTime
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                guard !event.isARepeat else { return event }
                let ch = event.characters?.lowercased()
                if event.type == .keyDown {
                    if ch == "z" { keyer.ditTime = timingController.ditTime; keyer.ditDown() }
                    else if ch == "x" { keyer.ditTime = timingController.ditTime; keyer.dahDown() }
                } else if event.type == .keyUp {
                    if ch == "z" { keyer.ditUp() }
                    else if ch == "x" { keyer.dahUp() }
                }
                return event
            }
        }
        .onDisappear {
            if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
            keyer.clear()
        }
    }

    private var outputDisplay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Keying:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(keyer.currentChar.isEmpty ? "—" : keyer.currentChar)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.green)
                    .shadow(color: keyer.isDitActive || keyer.isDahActive ? .green.opacity(0.9) : .clear, radius: 5)
                    .shadow(color: keyer.isDitActive || keyer.isDahActive ? .green.opacity(0.4) : .clear, radius: 14)
            }

            if !keyer.history.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(keyer.history, id: \.id) { entry in
                            VStack(spacing: 2) {
                                Text(entry.morse)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(entry.letter)
                                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(height: 50)
            }

            Text(keyer.decodedText.isEmpty ? " " : keyer.decodedText)
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
