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

        init() {
            convertToMorse()
        }

        public func convertToMorse() {
            morseCode = Morse.morse(from: morseText)
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
            case .dit:   Text("dit")
            case .dah:   Text("dah")
            case .infraSpace:  Text("_")
            case .letterSpace: Text("___")
            case .wordSpace:   Text("_______")
            }
        }
    }

    struct MorseFlasherView: View {
        @ObservedObject var conductor: Conductor

        private let baseWidth: CGFloat = 28

        var body: some View {
            ZStack {
                Color(white: 0.08)

                if conductor.tones.isEmpty {
                    Text("Type text above to see morse here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    let minDur = conductor.tones.map(\.tone.duration).min() ?? 0.01
                    let currentID = conductor.currentTone?.id ?? -1

                    GeometryReader { geo in
                        let halfW = geo.size.width / 2
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    Color.clear.frame(width: halfW, height: 1)
                                    ForEach(conductor.tones, id: \.id) { t in
                                        flasherCell(t, minDuration: minDur, currentID: currentID)
                                    }
                                    Color.clear.frame(width: halfW, height: 1)
                                }
                            }
                            .onChange(of: conductor.currentTone?.id) { _, id in
                                if let id {
                                    withAnimation(.easeInOut(duration: 0.12)) {
                                        proxy.scrollTo(id, anchor: .center)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        @ViewBuilder
        private func flasherCell(_ t: Conductor.SequencedTone, minDuration: Double, currentID: Int) -> some View {
            let isActive   = t.id == currentID
            let isPlayed   = t.id < currentID
            let isSounding = t.tone.amplitude > 0
            let isInfra    = t.tone.morse == Morse.Symbols.infraSpace.rawValue
            let cellWidth  = max(baseWidth, baseWidth * CGFloat(t.tone.duration / minDuration))

            ZStack {
                // Active bloom
                if isActive && isSounding {
                    Color.red
                        .blur(radius: 40)
                        .opacity(0.45)
                        .allowsHitTesting(false)
                }

                if isSounding {
                    Text(t.tone.morse)
                        .font(.system(size: isActive ? 44 : 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(
                            isActive  ? Color.white :
                            isPlayed  ? Color.primary.opacity(0.25) :
                                        Color.primary.opacity(0.55)
                        )
                        .shadow(color: isActive ? .white.opacity(0.9)  : .clear, radius: 3)
                        .shadow(color: isActive ? .red.opacity(0.8)    : .clear, radius: 10)
                        .shadow(color: isActive ? .red.opacity(0.4)    : .clear, radius: 24)
                        .animation(.easeInOut(duration: 0.04), value: isActive)
                } else if isInfra {
                    Rectangle()
                        .fill(
                            isActive  ? Color.white.opacity(0.8) :
                            isPlayed  ? Color.primary.opacity(0.08) :
                                        Color.primary.opacity(0.18)
                        )
                        .frame(width: 1.5)
                        .padding(.vertical, 20)
                } else {
                    // Letter / word space badge
                    flasherSpaceLabel(for: t, isActive: isActive, isPlayed: isPlayed)
                }
            }
            .frame(width: cellWidth, height: 80)
            .id(t.id)
        }

        @ViewBuilder
        private func flasherSpaceLabel(for t: Conductor.SequencedTone, isActive: Bool, isPlayed: Bool) -> some View {
            let opacity: Double = isActive ? 1.0 : isPlayed ? 0.2 : 0.5
            if t.tone.morse == Morse.Symbols.wordSpace.rawValue {
                Text("W")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isActive ? Color.white : Color.blue)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3)
                        .fill(isActive ? Color.red.opacity(0.4) : Color.blue.opacity(0.15)))
                    .opacity(opacity)
            } else if t.tone.morse == Morse.Symbols.letterSpace.rawValue {
                Text("L")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isActive ? Color.white : Color.red)
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3)
                        .fill(isActive ? Color.red.opacity(0.4) : Color.red.opacity(0.12)))
                    .opacity(opacity)
            }
        }
    }
}

class HoverWatcher: ObservableObject {
    @Published var hoveredTone: Conductor.SequencedTone? = nil
    @Published var hoveredWordID: Int? = nil
}

struct ContentView: View {

    // These are owned by the view, not handed to it — @ObservedObject on an inline
    // initializer makes the object a fresh instance every time the struct is rebuilt.
    @StateObject private var morseController = Controllers.MorseController()
    @StateObject private var conductor = Conductor()
    @StateObject private var timingController = Controllers.TimingController()
    @StateObject private var hoverWatcher = HoverWatcher()

    @State private var scrollPosition: Int? = 0
    @State private var isShowingSettings = false
    @State private var isShowingKeyer = false
    @State private var isShowingPractice = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            inputSection
            Divider()
            Views.MorseFlasherView(conductor: conductor)
                .frame(minHeight: 120, maxHeight: 180)
                .onChange(of: conductor.currentTone) { _, _ in
                    scrollPosition = scrollPosition == nil ? 0 : (scrollPosition! + 1)
                }
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
            scrollPosition = 0
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
        }
        .padding()
    }

    // MARK: - Morse scroll strip

    private func wordGroups(from tones: [Conductor.SequencedTone]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var wordID = 0
        for t in tones {
            if t.tone.morse == Morse.Symbols.wordSpace.rawValue {
                wordID += 1
            } else {
                result[t.id] = wordID
            }
        }
        return result
    }

    private var wordLatinText: [Int: String] {
        let words = morseController.morseText.components(separatedBy: " ").filter { !$0.isEmpty }
        return Dictionary(uniqueKeysWithValues: words.enumerated().map { ($0.offset, $0.element) })
    }

    private func wordBounds(wordID: Int, tones: [Conductor.SequencedTone], groups: [Int: Int], minDuration: Double) -> (xOffset: CGFloat, width: CGFloat) {
        let baseW: CGFloat = 16
        let spacing: CGFloat = 3
        var x: CGFloat = 0
        var startX: CGFloat? = nil
        var endX: CGFloat = 0
        for t in tones {
            let w = max(baseW, baseW * CGFloat(t.tone.duration / minDuration))
            if groups[t.id] == wordID {
                if startX == nil { startX = x }
                endX = x + w
            }
            x += w + spacing
        }
        guard let sx = startX else { return (0, 0) }
        return (sx, endX - sx)
    }

    /// Breathing room for the active cell's shadow, which reaches ~11pt past the
    /// cell (radius 9 on the glyph, 6 on the plate).
    private let glowInset: CGFloat = 12

    private var morseScrollStrip: some View {
        let minDur = conductor.tones.map(\.tone.duration).min() ?? 0.01
        let groups = wordGroups(from: conductor.tones)
        return ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    ForEach(conductor.tones, id: \.id) { t in
                        toneCellView(t, minDuration: minDur, wordGroupID: groups[t.id])
                    }
                }
                .padding(.horizontal)
                .overlay(alignment: .topLeading) {
                    if let hoveredID = hoverWatcher.hoveredWordID,
                       let latinWord = wordLatinText[hoveredID] {
                        let b = wordBounds(wordID: hoveredID, tones: conductor.tones, groups: groups, minDuration: minDur)
                        Text(latinWord)
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(Color.white.opacity(0.48))
                            .frame(width: b.width, height: 64, alignment: .center)
                            .offset(x: 16 + b.xOffset)
                            .allowsHitTesting(false)
                    }
                }
                // The active cell's glow is drawn outside its 64pt frame, and the
                // scroll view clips at its bounds — without this the highlight was
                // sheared flat top and bottom. Applied after the overlay so the
                // word label keeps aligning to the cells rather than to the padding.
                .padding(.vertical, glowInset)

                if !conductor.tones.isEmpty {
                    timeRulerView(
                        tones: conductor.tones,
                        minDuration: minDur,
                        currentID: conductor.currentTone?.id ?? -1
                    )
                    .padding(.horizontal)
                }
            }
        }
        .frame(height: 96 + glowInset * 2)
        .background(.background.secondary)
        .scrollPosition(id: $scrollPosition)
    }

    private func timeRulerView(tones: [Conductor.SequencedTone], minDuration: Double, currentID: Int) -> some View {
        let baseW: CGFloat = 16
        let spacing: CGFloat = 3

        var totalWidth: CGFloat = 0
        for (i, t) in tones.enumerated() {
            totalWidth += max(baseW, baseW * CGFloat(t.tone.duration / minDuration))
            if i < tones.count - 1 { totalWidth += spacing }
        }

        var currentX: CGFloat = -1
        var cx: CGFloat = 0
        for t in tones {
            let w = max(baseW, baseW * CGFloat(t.tone.duration / minDuration))
            if t.id == currentID { currentX = cx + w / 2; break }
            cx += w + spacing
        }

        return Canvas { ctx, size in
            ctx.stroke(Path { p in
                p.move(to: .init(x: 0, y: 0))
                p.addLine(to: .init(x: size.width, y: 0))
            }, with: .color(.primary.opacity(0.45)), lineWidth: 0.5)

            if currentX >= 0 {
                ctx.stroke(Path { p in
                    p.move(to: .init(x: currentX, y: 0))
                    p.addLine(to: .init(x: currentX, y: size.height))
                }, with: .color(.green.opacity(0.9)), lineWidth: 1.5)
            }

            var xPos: CGFloat = 0
            var tick = 0
            while xPos <= totalWidth {
                let major = tick % 5 == 0
                ctx.stroke(Path { p in
                    p.move(to: .init(x: xPos, y: 0))
                    p.addLine(to: .init(x: xPos, y: major ? 7 : 3.5))
                }, with: .color(.primary.opacity(major ? 0.75 : 0.35)), lineWidth: major ? 1 : 0.5)

                if major && tick > 0 {
                    let t = minDuration * Double(tick)
                    let label = t >= 1 ? String(format: "%.1fs", t) : String(format: "%dms", Int(t * 1000))
                    ctx.draw(
                        Text(label).font(.system(size: 7, weight: .medium, design: .monospaced)).foregroundStyle(Color.primary.opacity(0.75)),
                        at: .init(x: xPos, y: 13)
                    )
                }
                xPos += baseW
                tick += 1
            }
        }
        .frame(width: totalWidth, height: 18)
    }

    private func toneCellView(_ t: Conductor.SequencedTone, minDuration: Double, wordGroupID: Int?) -> some View {
        let isActive    = conductor.currentTone?.id == t.id
        let isSounding  = t.tone.amplitude > 0
        let isInfra     = t.tone.morse == Morse.Symbols.infraSpace.rawValue
        let isWordHover = wordGroupID != nil && hoverWatcher.hoveredWordID == wordGroupID
        let cellWidth   = max(16, 16.0 * CGFloat(t.tone.duration / minDuration))

        let tooltip: String = {
            if isInfra { return "Intra-character space · 1 dit" }
            if t.tone.morse == Morse.Symbols.letterSpace.rawValue { return "Letter space · 3 dits" }
            if t.tone.morse == Morse.Symbols.wordSpace.rawValue   { return "Word space · 7 dits" }
            return ""
        }()

        return ZStack {
            // Word-hover background (behind active highlight)
            if isWordHover {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue.opacity(0.12))
            }

            RoundedRectangle(cornerRadius: 4)
                .fill(isActive ? Color.green.opacity(0.12) : Color.clear)
                .shadow(color: isActive ? .green.opacity(0.7) : .clear, radius: 6)

            if isSounding {
                VStack(spacing: 1) {
                    if hoverWatcher.hoveredTone?.id == t.id {
                        Text(t.tone.duration, format: .number.precision(.fractionLength(3)))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    Text(t.tone.morse)
                        .font(.system(size: 21, weight: .bold, design: .monospaced))
                        .foregroundStyle(isActive ? Color.green : Color.primary)
                        .shadow(color: isActive ? .green.opacity(0.95) : .clear, radius: 3)
                        .shadow(color: isActive ? .green.opacity(0.55) : .clear, radius: 9)
                }
            } else if isInfra {
                Rectangle()
                    .fill(isActive ? Color.green.opacity(0.7) : Color.primary.opacity(0.18))
                    .frame(width: 1.5)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 2) {
                    if hoverWatcher.hoveredTone?.id == t.id {
                        Text(t.tone.duration, format: .number.precision(.fractionLength(3)))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    spaceLabel(for: t, isActive: isActive)
                }
            }
        }
        .frame(width: cellWidth, height: 64)
        .help(tooltip)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                hoverWatcher.hoveredTone = t
                hoverWatcher.hoveredWordID = wordGroupID
            case .ended:
                hoverWatcher.hoveredTone = nil
                hoverWatcher.hoveredWordID = nil
            }
        }
    }

    @ViewBuilder
    private func spaceLabel(for t: Conductor.SequencedTone, isActive: Bool) -> some View {
        if t.tone.morse == Morse.Symbols.wordSpace.rawValue {
            Text("W")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? .green : .blue)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3)
                    .fill(isActive ? Color.green.opacity(0.2) : Color.blue.opacity(0.15)))
        } else if t.tone.morse == Morse.Symbols.letterSpace.rawValue {
            Text("L")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? .green : .red)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3)
                    .fill(isActive ? Color.green.opacity(0.2) : Color.red.opacity(0.15)))
        }
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
                Text("\(Int(Farnsworth.wpm(ditTime: timingController.ditTime).rounded())) wpm")
                    .fontWeight(.medium)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Button {
                if conductor.isPlaying {
                    Task { await conductor.stop() }
                } else {
                    scrollPosition = 0
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
