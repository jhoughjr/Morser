//
//  MorseStripView.swift
//  MorserX
//
//  The sequencer strip, drawn as a timing diagram.
//
//  It used to draw every element as a glyph of roughly equal weight: a "." for a
//  dit, a "-" for a dah, a hairline for the gap inside a character, and lettered
//  badges for the gaps between them. Five kinds of mark, all about as loud as each
//  other, so nothing stood out — you had to read it symbol by symbol, which is
//  exactly what a picture of morse should save you from.
//
//  Sound is now the only thing with ink. A dit is a short bar, a dah is a bar
//  three times as long, and silence is empty space of the right width — so the
//  gaps that separate characters and words read as gaps instead of as more
//  symbols. The letter each group spells sits underneath it.
//

import SwiftUI
import Morse

// MARK: - Layout

/// Turns a tone sequence into positioned bars and character groups.
///
/// Kept separate from the view because the arithmetic — where a bar starts, which
/// bars belong to which character, how wide the whole thing is — is the part that
/// can be quietly wrong.
enum StripLayout {

    struct Bar: Equatable {
        let id: Int
        let x: CGFloat
        let width: CGFloat
        /// Dahs are drawn heavier; at a glance the length already says it, but the
        /// weight makes it legible when the strip is scrolling.
        let isDah: Bool
    }

    /// One character's worth of bars, plus the letter it spells.
    struct Group: Equatable {
        let index: Int
        let x: CGFloat
        let width: CGFloat
        let label: String?
        let ids: [Int]
    }

    struct Model: Equatable {
        var bars: [Bar] = []
        var groups: [Group] = []
        /// x positions of the gaps between words, for the divider.
        var wordBreaks: [CGFloat] = []
        var width: CGFloat = 0
        /// Points per second, so a ruler can be drawn against the same scale.
        var pointsPerSecond: CGFloat = 0
    }

    /// - Parameter unit: points given to one dit. Everything else is proportional,
    ///   which is what makes the picture a timing diagram rather than a row of cells.
    static func build(tones: [Conductor.SequencedTone],
                      labels: [String],
                      unit: CGFloat = 9) -> Model {
        guard !tones.isEmpty else { return Model() }

        let ditDuration = tones.map(\.tone.duration).min() ?? 0.1
        guard ditDuration > 0 else { return Model() }
        let scale = unit / ditDuration

        var model = Model()
        model.pointsPerSecond = scale

        var x: CGFloat = 0
        var groupStart: CGFloat = 0
        var groupIDs: [Int] = []
        var groupIndex = 0

        func closeGroup(endingAt end: CGFloat) {
            guard !groupIDs.isEmpty else { return }
            model.groups.append(Group(index: groupIndex,
                                      x: groupStart,
                                      width: end - groupStart,
                                      label: groupIndex < labels.count ? labels[groupIndex] : nil,
                                      ids: groupIDs))
            groupIndex += 1
            groupIDs = []
        }

        for sequenced in tones {
            let tone = sequenced.tone
            let width = CGFloat(tone.duration) * scale

            if tone.amplitude > 0 {
                if groupIDs.isEmpty { groupStart = x }
                model.bars.append(Bar(id: sequenced.id,
                                      x: x,
                                      width: width,
                                      isDah: tone.morse == Morse.Symbols.dah.rawValue))
                groupIDs.append(sequenced.id)
            } else if tone.morse == Morse.Symbols.letterSpace.rawValue {
                closeGroup(endingAt: x)
            } else if tone.morse == Morse.Symbols.wordSpace.rawValue {
                closeGroup(endingAt: x)
                model.wordBreaks.append(x + width / 2)
            }

            x += width
        }
        closeGroup(endingAt: x)

        model.width = x
        return model
    }
}

// MARK: - View

struct MorseStripView: View {

    let tones: [Conductor.SequencedTone]
    let currentID: Int
    /// What each group spells, in order — one per group. A prosign is one group
    /// and one label, which is why these are strings rather than characters.
    let labels: [String]

    @Binding var hoveredGroup: Int?

    private let unit: CGFloat = 9
    private let laneHeight: CGFloat = 46
    private let barHeight: CGFloat = 22

    static let height: CGFloat = 108

    var body: some View {
        let model = StripLayout.build(tones: tones, labels: labels, unit: unit)

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    groupBackgrounds(model)
                    wordDividers(model)
                    bars(model)
                    letterRow(model)
                    ruler(model)
                    // Zero-width markers the scroll view can aim at; the bars
                    // themselves are placed by offset and have no position of
                    // their own to scroll to.
                    anchors(model)
                }
                // Room for the active bar's glow, which is drawn outside the bar.
                .frame(width: model.width + 32, height: Self.height, alignment: .topLeading)
                .padding(.horizontal, 16)
            }
            .onChange(of: currentID) { _, id in
                guard let group = model.groups.first(where: { $0.ids.contains(id) }) else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    proxy.scrollTo(group.index, anchor: .center)
                }
            }
        }
        .frame(height: Self.height)
        .background(Color(white: 0.09))
    }

    // MARK: Pieces

    private func groupBackgrounds(_ model: StripLayout.Model) -> some View {
        ForEach(model.groups, id: \.index) { group in
            let isActive = group.ids.contains(currentID)
            let isHovered = hoveredGroup == group.index
            RoundedRectangle(cornerRadius: 5)
                .fill(isActive ? Color.green.opacity(0.10)
                      : isHovered ? Color.white.opacity(0.07) : Color.clear)
                .frame(width: group.width + 8, height: laneHeight + 22)
                .offset(x: group.x - 4, y: 4)
                .onHover { inside in
                    hoveredGroup = inside ? group.index : (hoveredGroup == group.index ? nil : hoveredGroup)
                }
        }
    }

    private func anchors(_ model: StripLayout.Model) -> some View {
        ForEach(model.groups, id: \.index) { group in
            Color.clear
                .frame(width: max(group.width, 1), height: 1)
                .offset(x: group.x)
                .id(group.index)
        }
    }

    private func wordDividers(_ model: StripLayout.Model) -> some View {
        ForEach(Array(model.wordBreaks.enumerated()), id: \.offset) { _, x in
            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: laneHeight + 14)
                .offset(x: x, y: 4)
        }
    }

    private func bars(_ model: StripLayout.Model) -> some View {
        ForEach(model.bars, id: \.id) { bar in
            let isActive = bar.id == currentID
            let isPlayed = bar.id < currentID
            RoundedRectangle(cornerRadius: 3)
                .fill(isActive ? Color.green
                      : isPlayed ? Color.white.opacity(0.22)
                                 : Color.white.opacity(0.62))
                .frame(width: max(bar.width, 3), height: bar.isDah ? barHeight : barHeight * 0.78)
                .shadow(color: isActive ? .green.opacity(0.85) : .clear, radius: 7)
                .shadow(color: isActive ? .green.opacity(0.35) : .clear, radius: 16)
                .offset(x: bar.x,
                        y: (laneHeight - (bar.isDah ? barHeight : barHeight * 0.78)) / 2 + 4)
                .animation(.easeOut(duration: 0.06), value: isActive)
        }
    }

    private func letterRow(_ model: StripLayout.Model) -> some View {
        ForEach(model.groups, id: \.index) { group in
            let isActive = group.ids.contains(currentID)
            let isPlayed = (group.ids.last ?? 0) < currentID
            Text(group.label ?? "·")
                .font(.system(size: 15, weight: isActive ? .bold : .medium, design: .monospaced))
                .foregroundStyle(isActive ? Color.green
                                 : isPlayed ? Color.white.opacity(0.3)
                                            : Color.white.opacity(0.65))
                .frame(width: max(group.width, 10), alignment: .center)
                .offset(x: group.x, y: laneHeight + 8)
        }
    }

    /// One tick a second, labelled. The old ruler ticked once per dit, which at
    /// speed put a tick under every few pixels and read as texture, not as time.
    private func ruler(_ model: StripLayout.Model) -> some View {
        let seconds = Int((model.width / max(model.pointsPerSecond, 1)).rounded(.up))
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: model.width, height: 1)
                .offset(y: laneHeight + 32)

            ForEach(0...max(seconds, 0), id: \.self) { second in
                let x = CGFloat(second) * model.pointsPerSecond
                if x <= model.width {
                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 1, height: 4)
                        Text("\(second)s")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                            .fixedSize()
                    }
                    .offset(x: x, y: laneHeight + 33)
                }
            }
        }
    }
}
