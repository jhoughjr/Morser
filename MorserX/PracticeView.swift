//
//  PracticeView.swift
//  MorserX
//
//  The trainer. It sends a few groups, takes your copy, and marks it — and it
//  deliberately won't show you the morse while it's sending. The sequencer strip
//  in the main window is a study aid; here it would just be the answer key.
//

import SwiftUI
import Morse

struct PracticeView: View {

    @StateObject private var session: PracticeSession
    @ObservedObject private var conductor: Conductor

    @FocusState private var answerFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(conductor: Conductor, session: PracticeSession = PracticeSession()) {
        self.conductor = conductor
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    alphabetSection
                    speedSection
                    Divider()
                    roundSection
                    if session.phase == .graded, let grade = session.grade {
                        gradeSection(grade)
                    }
                    if !session.weakest.isEmpty {
                        Divider()
                        weakestSection
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 520, minHeight: 560)
        .onDisappear {
            Task { await conductor.stop() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Practice")
                    .font(.headline)
                Text("Koch method · level \(session.level) of \(PracticeSession.kochOrder.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Section headings

    /// One shape for every section heading, so the icons read as a set rather
    /// than as decoration applied one at a time.
    private func sectionHeading(_ title: String, systemImage: String, tint: Color = .accentColor) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(title)
                .font(.subheadline).fontWeight(.semibold)
        }
    }

    // MARK: - Alphabet

    private var alphabetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeading("In play", systemImage: "character.book.closed")
                Spacer()
                Button {
                    session.retreat()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(session.level <= PracticeSession.minimumLevel)

                Button {
                    session.advance()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(session.nextCharacter == nil)
            }

            // A wrapping row would need a layout; the alphabet is short enough
            // that a scroller is honest and costs nothing.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(session.alphabet, id: \.self) { char in
                        characterChip(char)
                    }
                    if let next = session.nextCharacter {
                        Text(String(next))
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.04)))
                            .foregroundStyle(.quaternary)
                            .help("Unlocked at \(Int(PracticeSession.advanceThreshold * 100))% accuracy")
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func characterChip(_ char: Character) -> some View {
        let score = session.scores[char]
        let tint: Color = {
            guard let score, score.attempts > 0 else { return .secondary }
            return score.accuracy >= 0.9 ? .green : score.accuracy >= 0.7 ? .yellow : .red
        }()
        return Text(String(char))
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 5).fill(tint.opacity(0.16)))
            .foregroundStyle(tint == .secondary ? Color.primary : tint)
            .help(score.map { "\($0.hits)/\($0.attempts) correct" } ?? "not heard yet")
    }

    // MARK: - Speed

    private var speedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Speed", systemImage: "speedometer", tint: .orange)
                .padding(.bottom, 2)

            HStack {
                Text("Character speed")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(session.characterWPM)) wpm")
                    .font(.caption).monospacedDigit()
            }
            Slider(value: $session.characterWPM, in: 10...35, step: 1)

            HStack {
                Text("Effective speed")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(session.effectiveWPM)) wpm")
                    .font(.caption).monospacedDigit()
            }
            Slider(value: $session.effectiveWPM, in: 5...35, step: 1)

            Text("Characters are sent at full speed; the gaps between them carry the difference.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Round

    private var roundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Copy", systemImage: "ear.badge.waveform", tint: .blue)

            HStack(spacing: 10) {
                Button {
                    startRound()
                } label: {
                    Label(session.phase == .ready ? "Send" : "New round", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.phase == .sending)

                Button {
                    replay()
                } label: {
                    Label("Replay", systemImage: "arrow.counterclockwise")
                }
                .disabled(session.prompt.isEmpty || session.phase == .sending)

                Stepper("\(session.groupCount)×\(session.groupSize)", value: $session.groupCount, in: 1...10)
                    .font(.caption)
                    .fixedSize()
            }

            if session.phase == .sending {
                Label("Sending — listen", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            TextField("Type what you hear…", text: $session.answer)
                .textFieldStyle(.roundedBorder)
                .font(.system(.title3, design: .monospaced))
                .textCase(.uppercase)
                .disabled(session.phase == .sending || session.phase == .ready)
                .focused($answerFocused)
                .onSubmit { session.submit() }

            if session.phase == .answering {
                Text("Return to check")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func startRound() {
        session.startRound()
        play()
    }

    private func replay() {
        session.replay()
        play()
    }

    private func play() {
        let morse = session.promptMorse
        let dit = session.ditTime
        let spacing = session.spaceDitTime
        Task { @MainActor in
            await conductor.send(morse: morse, with: dit, spaceDitTime: spacing)
            await conductor.waitForSending()
            session.finishedSending()
            answerFocused = true
        }
    }

    // MARK: - Grade

    private func gradeSection(_ grade: Grade) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Marked",
                           systemImage: grade.accuracy >= PracticeSession.advanceThreshold
                               ? "checkmark.seal.fill" : "pencil.and.list.clipboard",
                           tint: grade.accuracy >= PracticeSession.advanceThreshold ? .green : .secondary)

            HStack {
                Text("\(Int((grade.accuracy * 100).rounded()))%")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(grade.accuracy >= PracticeSession.advanceThreshold ? .green : .primary)
                Text("\(grade.hits) of \(grade.total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if session.canAdvance, let next = session.nextCharacter {
                    Button {
                        session.advance()
                        startRound()
                    } label: {
                        Label("Add \(String(next))", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(grade.groups.enumerated()), id: \.offset) { _, group in
                        HStack(spacing: 3) {
                            ForEach(Array(group.enumerated()), id: \.offset) { _, cell in
                                gradeCell(cell)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func gradeCell(_ cell: Grade.Cell) -> some View {
        VStack(spacing: 2) {
            Text(cell.expected.map(String.init) ?? "·")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(cell.isHit ? Color.green : Color.primary)
            // Only worth showing what was typed when it differs from what was sent.
            Text(cell.isHit ? " " : (cell.heard.map(String.init) ?? "–"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.red)
        }
        .frame(width: 22)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(cell.isHit ? Color.green.opacity(0.12) : Color.red.opacity(0.10)))
    }

    // MARK: - Weakest

    private var weakestSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeading("Worst first", systemImage: "chart.bar.xaxis", tint: .red)
                Spacer()
                Button("Reset stats") { session.resetScores() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            ForEach(session.weakest.prefix(5), id: \.character) { entry in
                HStack(spacing: 8) {
                    Text(String(entry.character))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .frame(width: 16, alignment: .leading)
                    ProgressView(value: entry.score.accuracy)
                        .tint(entry.score.accuracy >= 0.9 ? .green : entry.score.accuracy >= 0.7 ? .yellow : .red)
                    Text("\(Int((entry.score.accuracy * 100).rounded()))%")
                        .font(.caption2).monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
    }
}
