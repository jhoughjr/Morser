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

    @State private var recorder = FistRecorder()
    @State private var isKeyDown = false
    @State private var deadlineElapsed: Double = 0
    @State private var keyMonitor: Any?
    @State private var deadlineTask: Task<Void, Never>?

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
                    modeSection
                    if !session.alphabet.isEmpty || session.drill.usesLevels {
                        alphabetSection
                    }
                    speedSection
                    Divider()
                    roundSection
                    if session.phase == .graded, let grade = session.grade {
                        gradeSection(grade)
                    }
                    if session.phase == .graded, let report = session.fistReport {
                        Divider()
                        fistSection(report)
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
        .onChange(of: session.phase) { _, phase in
            phase == .answering ? beginAnswering() : endAnswering()
        }
        .onDisappear {
            endAnswering()
            Task { await conductor.stop() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Practice")
                    .font(.headline)
                Text(session.drill.usesLevels
                     ? "\(session.mode.title) · level \(session.level) of \(PracticeSession.kochOrder.count)"
                     : session.mode.summary)
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

    // MARK: - Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading("Drill", systemImage: "dial.medium", tint: .purple)

            Picker("", selection: $session.mode) {
                ForEach(PracticeMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch session.mode {
            case .characterSet:
                Picker("Set", selection: $session.characterSet) {
                    ForEach(CharacterSetChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .fixedSize()

            case .custom:
                TextField("Text to drill against", text: $session.customText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2...4)

            case .koch, .callsigns, .qso, .words, .headCopy, .instant, .sending:
                EmptyView()
            }
        }
    }

    // MARK: - Alphabet

    private var alphabetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeading("In play", systemImage: "character.book.closed")
                Spacer()
                if session.drill.usesLevels {
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

            Toggle(isOn: $session.speedLadder) {
                Text("Speed up after \(PracticeSession.ladderStreak) clean rounds")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .help("Knowing when to push the speed is the judgement a learner hasn't got yet")
        }
    }

    // MARK: - Round

    private var roundSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Copy", systemImage: "ear.badge.waveform", tint: .blue)

            HStack(spacing: 10) {
                // Only one of these exists at a time, so Return can belong to
                // whichever step you're actually on.
                switch session.phase {
                case .ready, .graded:
                    Button {
                        startRound()
                    } label: {
                        Label(session.phase == .ready ? "Send" : "Next round", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)

                case .sending where session.answerMethod != .keyed:
                    Label("Sending — listen", systemImage: "waveform")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)

                case .sending:
                    EmptyView()

                case .answering:
                    if session.answerMethod == .keyed {
                        Button {
                            markKeyedRound()
                        } label: {
                            Label("Mark it", systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(recorder.presses.isEmpty)
                    } else if session.answerMethod == .typed {
                        Button {
                            submit()
                        } label: {
                            Label("Check", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.answer.isEmpty)
                    } else {
                        Label("Answer", systemImage: "questionmark.circle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                    }
                }

                Button {
                    replay()
                } label: {
                    Label("Replay", systemImage: "arrow.counterclockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(session.prompt.isEmpty || session.phase == .sending)

                Stepper(value: $session.groupCount, in: 1...10) {
                    Text("\(session.groupCount) groups").font(.caption)
                }
                .fixedSize()

                Stepper(value: $session.groupSize, in: 1...7) {
                    Text("of \(session.groupSize)").font(.caption)
                }
                .fixedSize()
            }

            switch session.answerMethod {
            case .typed:
                TextField("Type what you hear…", text: $session.answer)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.title3, design: .monospaced))
                    .disabled(session.phase == .sending || session.phase == .ready)
                    .focused($answerFocused)
                    .onSubmit { submit() }

            case .selfReported:
                selfReportRow

            case .singleKey:
                singleKeyRow

            case .keyed:
                straightKeyRow
            }

            HStack {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                if session.roundsThisSession > 0 {
                    sessionSummary
                }
            }
        }
    }

    private var hint: String {
        switch session.phase {
        case .ready:     return "Return to send · ⌘R to replay"
        case .sending:   return "…"
        case .answering:
            switch session.answerMethod {
            case .typed:        return "Return to check"
            case .selfReported: return "Did you get it?"
            case .singleKey:    return "Press the character you heard"
            case .keyed:        return "Hold space (or the key below) to send · Return to mark it"
            }
        case .graded:    return "Return for the next round"
        }
    }

    // MARK: - Head copy

    /// No text field on purpose. Somewhere to write is the thing head copy is
    /// trying to take away.
    private var selfReportRow: some View {
        HStack(spacing: 10) {
            Button {
                session.submit(selfReported: true)
                answerFocused = false
            } label: {
                Label("Got it", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .keyboardShortcut("j", modifiers: [])

            Button {
                session.submit(selfReported: false)
                answerFocused = false
            } label: {
                Label("Missed it", systemImage: "xmark.circle.fill")
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("f", modifiers: [])
        }
        .disabled(session.phase != .answering)
        .opacity(session.phase == .answering ? 1 : 0.35)
    }

    // MARK: - Straight key

    /// One control, and the length of the press is yours.
    ///
    /// The paddle in the keyer sheet auto-streams dits on a timer, so its timing
    /// is the machine's rather than the operator's — there is no fist to grade on
    /// an input that is already perfect.
    private var straightKeyRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.prompt.uppercased())
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 6)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isKeyDown ? Color.green : Color.green.opacity(0.12))
                    .shadow(color: isKeyDown ? .green.opacity(0.7) : .clear, radius: 16)
                    .animation(.easeInOut(duration: 0.04), value: isKeyDown)

                VStack(spacing: 4) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 26, weight: .semibold))
                    Text("hold to send · space")
                        .font(.caption2)
                }
                .foregroundStyle(isKeyDown ? .white : .green)
            }
            .frame(height: 88)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in keyDown() }
                    .onEnded { _ in keyUp() }
            )

            Text(recorder.presses.isEmpty
                 ? "Nothing keyed yet"
                 : "\(recorder.presses.count) elements sent")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .disabled(session.phase != .answering)
        .opacity(session.phase == .answering ? 1 : 0.4)
    }

    private func keyDown() {
        guard session.phase == .answering, !isKeyDown else { return }
        isKeyDown = true
        recorder.down(at: Date().timeIntervalSinceReferenceDate)
        conductor.player.keyDown()
    }

    private func keyUp() {
        guard isKeyDown else { return }
        isKeyDown = false
        recorder.up(at: Date().timeIntervalSinceReferenceDate)
        conductor.player.keyUp()
    }

    private func markKeyedRound() {
        guard !recorder.presses.isEmpty else { return }
        session.submitKeyed(presses: recorder.presses)
        recorder.reset()
        isKeyDown = false
    }

    /// What the fist looked like from outside — the half you can't hear yourself.
    private func fistSection(_ report: FistReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeading("Your fist",
                           systemImage: report.isClean ? "hand.thumbsup.fill" : "waveform.badge.exclamationmark",
                           tint: report.isClean ? .green : .orange)

            HStack(spacing: 14) {
                Label(String(format: "%.0f wpm", report.wpm), systemImage: "speedometer")
                if let dahRatio = report.dahRatio {
                    Label(String(format: "dah %.1f×", dahRatio), systemImage: "minus")
                }
                if let letterGap = report.letterGapRatio {
                    Label(String(format: "letter gap %.1f×", letterGap), systemImage: "space")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()

            if report.isClean {
                Text("Readable — nothing to fix.")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                ForEach(report.notes, id: \.self) { note in
                    Label(note, systemImage: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    // MARK: - Instant recognition

    private var singleKeyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if session.phase == .answering, let deadline = session.answerDeadline {
                // A bar rather than a number: you should be listening and
                // reacting, not reading a countdown.
                ProgressView(value: deadlineElapsed, total: deadline)
                    .tint(.orange)
                    .animation(.linear(duration: deadline), value: deadlineElapsed)
            } else {
                ProgressView(value: 0, total: 1).tint(.clear)
            }

            Text(session.phase == .answering ? "One key — no Return" : " ")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var sessionSummary: some View {
        HStack(spacing: 10) {
            Label("\(session.roundsThisSession)", systemImage: "number")
            Label("\(Int((session.sessionAccuracy * 100).rounded()))%", systemImage: "target")
            if session.streak > 1 {
                Label("\(session.streak)", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
            }
            if let latency = session.lastLatency {
                Label(String(format: "%.2fs", latency), systemImage: "stopwatch")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .help("Rounds this session · running accuracy · consecutive clean rounds")
    }

    private func startRound() {
        session.startRound()
        play()
    }

    // MARK: - Answering

    private func beginAnswering() {
        if session.answerMethod == .keyed {
            recorder.reset()
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
                guard !event.isARepeat, event.charactersIgnoringModifiers == " " else { return event }
                event.type == .keyDown ? keyDown() : keyUp()
                return nil
            }
            return
        }

        guard session.answerMethod == .singleKey else { return }

        // One key, no Return: a text field would put an edit-and-confirm step in
        // front of what is supposed to be a reflex.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.isARepeat,
                  let character = event.charactersIgnoringModifiers?.first,
                  character.isLetter || character.isNumber || character.isPunctuation
            else { return event }

            session.answer = String(character)
            session.submit()
            return nil     // swallowed, so it can't also land in some other control
        }

        if let deadline = session.answerDeadline {
            deadlineElapsed = 0
            DispatchQueue.main.async { deadlineElapsed = deadline }
            deadlineTask = Task {
                try? await Task.sleep(for: .seconds(deadline))
                guard !Task.isCancelled, session.phase == .answering else { return }
                // Out of time is a miss. Right-after-thinking-about-it isn't
                // recognition, and scoring it as a hit would hide the only thing
                // this drill measures.
                session.answer = ""
                session.submit()
            }
        }
    }

    private func endAnswering() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if isKeyDown { keyUp() }
        deadlineTask?.cancel()
        deadlineTask = nil
        deadlineElapsed = 0
    }

    private func submit() {
        guard session.phase == .answering, !session.answer.isEmpty else { return }
        session.submit()
        answerFocused = false
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
                } else if let next = session.nextCharacter {
                    Text("\(Int(PracticeSession.advanceThreshold * 100))% unlocks \(String(next))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // The marked grid says the same thing, but seeing the two strings on
            // top of each other is how you spot a whole group heard one late.
            VStack(alignment: .leading, spacing: 2) {
                revealLine("sent", session.prompt, .secondary)
                if session.answerMethod == .typed {
                    revealLine("you", session.answer.uppercased(), .primary)
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

    private func revealLine(_ label: String, _ text: String, _ tint: HierarchicalShapeStyle) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 28, alignment: .trailing)
            Text(text.isEmpty ? "—" : text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(tint)
                .textSelection(.enabled)
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
