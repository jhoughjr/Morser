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

        let phaseStep = 2.0 * Double.pi * frequency / sampleRate

        for span in spans where span.isSounding && span.frameCount > 0 {
            let ramp = min(Int(rampSeconds * sampleRate), span.frameCount / 2)

            for i in 0..<span.frameCount {
                let frame = span.startFrame + i
                // Phase runs off the absolute frame index, so the sine stays continuous
                // across element boundaries and the envelope is the only thing shaping it.
                out[frame] = Float(sin(phaseStep * Double(frame)) * envelope(at: i, of: span.frameCount, ramp: ramp)) * amplitude
            }
        }

        for channel in 1..<Int(format.channelCount) {
            channels[channel].update(from: out, count: total)
        }

        return (buffer, spans)
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
