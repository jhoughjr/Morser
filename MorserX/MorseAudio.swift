//
//  MorseAudio.swift
//  MorserX
//
//  Sample-accurate morse rendering.
//
//  The old playback path timed itself with Task.sleep, which overshoots by
//  1–5ms per call and never undershoots. Because a dit and a dah issued the
//  same number of sleeps, they absorbed the same absolute error, so the 1:3:1
//  ratio that makes morse legible came out closer to 1:2.5:0.8 — and got worse
//  the faster you keyed. Here the sequence is laid out in integer frames and
//  handed to CoreAudio, which clocks it off the sample rate. Timing error stops
//  being a function of scheduler luck.
//

import AVFoundation
import Foundation

/// A tone's exact place in the rendered buffer, in frames.
struct ToneSpan: Equatable {
    let id: Int
    let startFrame: Int
    let frameCount: Int
    let isSounding: Bool

    var endFrame: Int { startFrame + frameCount }
}

/// Turns tones into samples. Pure and synchronous — no engine, no clock, no sleeping —
/// which is what makes the timing testable without audio hardware.
struct MorseRenderer {

    var sampleRate: Double = 48_000
    /// Sidetone pitch. 600Hz is the usual keyer sidetone; the old sawtooth at 440
    /// was all harmonics and got fatiguing fast.
    var frequency: Double = 600
    /// Edge length. ~5ms is the QSK convention: short enough to stay crisp,
    /// long enough to keep the key click out of the passband.
    var rampSeconds: Double = 0.005
    var amplitude: Float = 0.35

    // MARK: - Layout

    /// Frame layout for a tone sequence.
    ///
    /// Boundaries accumulate in floating point and round only at the edge, so a span
    /// sits at most half a frame off its ideal position and the error cannot compound
    /// across a transmission — element N starts where the sum of the first N durations
    /// says it should, not where the previous N roundings left off.
    func spans(for tones: [Tone]) -> [ToneSpan] {
        var spans: [ToneSpan] = []
        spans.reserveCapacity(tones.count)

        var exactEnd = 0.0
        var start = 0

        for (index, tone) in tones.enumerated() {
            exactEnd += tone.duration * sampleRate
            let end = Int(exactEnd.rounded())
            spans.append(ToneSpan(id: index,
                                  startFrame: start,
                                  frameCount: max(0, end - start),
                                  isSounding: tone.amplitude > 0))
            start = end
        }
        return spans
    }

    func totalFrames(for tones: [Tone]) -> Int {
        spans(for: tones).last?.endFrame ?? 0
    }

    // MARK: - Render

    /// Renders the whole transmission into one buffer.
    ///
    /// Returns the spans alongside it so the UI can locate itself by asking the audio
    /// clock where it is, rather than by driving playback and hoping the two agree.
    func render(_ tones: [Tone], format: AVAudioFormat) -> (buffer: AVAudioPCMBuffer, spans: [ToneSpan])? {
        let spans = spans(for: tones)
        let total = spans.last?.endFrame ?? 0

        guard total > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(total)),
              let channels = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(total)

        let out = channels[0]
        out.update(repeating: 0, count: total)

        // Phase is accumulated rather than computed from the frame index, because
        // elements can now differ in pitch: `sin(step × frame)` is only continuous
        // while `step` never changes, and a phase jump at a pitch change is a click
        // that no envelope can hide. Accumulating carries the waveform across the
        // boundary whatever the pitch does.
        var phase = 0.0

        for span in spans where span.frameCount > 0 {
            let step = 2.0 * Double.pi * pitch(for: span, in: tones) / sampleRate
            let ramp = min(Int(rampSeconds * sampleRate), span.frameCount / 2)
            let sounding = span.isSounding

            for i in 0..<span.frameCount {
                phase += step
                if phase > 2 * .pi { phase -= 2 * .pi }
                guard sounding else { continue }
                out[span.startFrame + i] =
                    Float(sin(phase) * envelope(at: i, of: span.frameCount, ramp: ramp)) * amplitude
            }
        }

        for channel in 1..<Int(format.channelCount) {
            channels[channel].update(from: out, count: total)
        }

        return (buffer, spans)
    }

    /// One transmission in a mix: its tones, where it starts, and how loud.
    struct Voice {
        let tones: [Tone]
        /// When this voice begins, in seconds from the start of the mix.
        var startSeconds: Double = 0
        /// Relative loudness. The wanted signal in a pileup sits above the rest.
        var gain: Float = 1
    }

    /// Renders several transmissions at once and sums them — the pileup.
    ///
    /// Each voice is rendered on its own (so it keeps its own pitch and timing),
    /// laid down at its frame offset, and added in. The sum is then scaled so its
    /// peak just reaches full scale: three signals summing to 1.05 would clip, and
    /// a clip is a much louder artefact than the crowding the drill is about.
    /// Scaling the whole mix by one factor keeps the voices' relative loudness,
    /// which is the cue you copy by.
    func renderMix(_ voices: [Voice], format: AVAudioFormat) -> (buffer: AVAudioPCMBuffer, frames: Int)? {
        let rendered: [(samples: [Float], offset: Int, gain: Float)] = voices.compactMap { voice in
            guard let (buffer, spans) = render(voice.tones, format: format),
                  let channel = buffer.floatChannelData?[0],
                  let total = spans.last?.endFrame, total > 0 else { return nil }
            return (Array(UnsafeBufferPointer(start: channel, count: total)),
                    Int((voice.startSeconds * sampleRate).rounded()),
                    voice.gain)
        }
        guard !rendered.isEmpty else { return nil }

        let mixed = Self.mix(rendered)
        guard !mixed.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(mixed.count)),
              let out = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(mixed.count)
        mixed.withUnsafeBufferPointer { source in
            out[0].update(from: source.baseAddress!, count: mixed.count)
            for channel in 1..<Int(format.channelCount) {
                out[channel].update(from: source.baseAddress!, count: mixed.count)
            }
        }
        return (buffer, mixed.count)
    }

    /// Sums placed, gained signals and normalises the peak to full scale.
    ///
    /// Pure and array-based so the mixing itself is testable without an engine —
    /// which matters, because clipping and off-by-one placement are exactly the
    /// faults that would still sound roughly right.
    static func mix(_ signals: [(samples: [Float], offset: Int, gain: Float)]) -> [Float] {
        let length = signals.map { $0.offset + $0.samples.count }.max() ?? 0
        guard length > 0 else { return [] }

        var out = [Float](repeating: 0, count: length)
        for signal in signals {
            let gain = signal.gain
            for (i, sample) in signal.samples.enumerated() {
                out[signal.offset + i] += sample * gain
            }
        }

        let peak = out.reduce(Float(0)) { max($0, abs($1)) }
        if peak > 1 {
            let scale = 1 / peak
            for i in out.indices { out[i] *= scale }
        }
        return out
    }

    /// The pitch an element is sounded at: its own, or the sidetone.
    private func pitch(for span: ToneSpan, in tones: [Tone]) -> Double {
        guard span.id < tones.count, let pitch = tones[span.id].pitch else { return frequency }
        return Double(pitch)
    }

    /// Raised cosine. Continuous in value *and* slope at both edges — a linear ramp
    /// is continuous in value only, and that corner is what you hear as a click.
    private func envelope(at i: Int, of count: Int, ramp: Int) -> Double {
        guard ramp > 0 else { return 1 }
        if i < ramp {
            return 0.5 * (1 - cos(Double.pi * Double(i) / Double(ramp)))
        }
        if i >= count - ramp {
            let mirrored = count - 1 - i
            return 0.5 * (1 - cos(Double.pi * Double(mirrored) / Double(ramp)))
        }
        return 1
    }
}
