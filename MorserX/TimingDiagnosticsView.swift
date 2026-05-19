import SwiftUI

struct TimingDiagnosticsView: View {
    @ObservedObject var player: Player
    @State private var sweepStart = 0.005
    @State private var sweepEnd = 0.1
    @State private var sweepStep = 0.005
    @State private var results: [(id:Int,ditTime: Double, expected: Double, actual: Double)] = []
    @State private var isTesting = false
    @State private var bufferSize: Double = 128 // Default buffer size
    @State private var customBuffer: Bool = false
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Morse Timing Diagnostics")
                .font(.title2)
                .padding(.bottom, 4)
            Text("Runs quick playback tests at different ditTime values. Compare expected vs. actual durations.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text("Sweep Start: ")
                Slider(value: $sweepStart, in: 0.001...sweepEnd, step: 0.001)
                    .frame(maxWidth: 150)
                Text(String(format: "%.3f", sweepStart))
            }
            HStack {
                Text("Sweep End: ")
                Slider(value: $sweepEnd, in: sweepStart...0.5, step: 0.001)
                    .frame(maxWidth: 150)
                Text(String(format: "%.3f", sweepEnd))
            }
            HStack {
                Text("Step: ")
                Slider(value: $sweepStep, in: 0.001...max(0.1, sweepEnd - sweepStart), step: 0.001)
                    .frame(maxWidth: 150)
                Text(String(format: "%.3f", sweepStep))
            }
            Divider()
            Toggle("Custom Buffer Size", isOn: $customBuffer)
            if customBuffer {
                HStack {
                    Text("Buffer Size: ")
                    Slider(value: $bufferSize, in: 32...1024, step: 32)
                        .frame(maxWidth: 200)
                    Text("\(Int(bufferSize)) frames")
                }
                Button("Apply Buffer Size") {
                    player.setManualRenderingBufferSize(bytes:UInt32(bufferSize))
                }
            }
            Divider()
            Button(isTesting ? "Testing..." : "Run Diagnostic") {
                Task {
                    isTesting = true
                    results = await player.diagnoseTiming(sweep: stride(from: sweepStart, through: sweepEnd, by: sweepStep).map { $0 })
                    isTesting = false
                }
            }
            .disabled(isTesting)
            .padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(results, id: \.id) { result in
                        HStack {
                            Text(String(format: "ditTime: %.3f s", result.ditTime))
                                .frame(width: 120, alignment: .leading)
                            Text(String(format: "expected: %.3f s", result.expected))
                                .frame(width: 120, alignment: .leading)
                            Text(String(format: "actual: %.3f s", result.actual))
                                .frame(width: 120, alignment: .leading)
                            let diff = result.actual - result.expected
                            Text(String(format: "diff: %.3f s", diff))
                                .foregroundColor(abs(diff) > 0.02 ? .red : .primary)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding()
    }
}

// Usage: Present TimingDiagnosticsView(player: <yourPlayerInstance>) in your app. Include in test build or advanced menu.
