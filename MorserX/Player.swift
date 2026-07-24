//
//  Player.swift
//  MorserX
//
//  Created by Jimmy Hough Jr on 12/16/24.
//
//  Hosts one AVAudioEngine for both jobs:
//
//    • transmissions — pre-rendered whole and scheduled on a player node, so
//      CoreAudio clocks the timing instead of Task.sleep
//    • the keyer sidetone — a source node gated in its render callback, so
//      key-down latency stays at one buffer instead of a task hop
//
//  Previously each of those ran its own AudioEngine (Conductor owned one, Keyer
//  owned another), which meant two render threads competing for the same device.
//

import AVFoundation
import SwiftUI

// MARK: - Sidetone state
//
// Touched by the render thread every callback. Kept in a class so the callback
// mutates one shared instance rather than a captured copy, and marked unchecked
// because the render thread is the only writer of phase/gain.
private final class SidetoneState: @unchecked Sendable {
    var phase: Double = 0
    var gain: Float = 0            // 0…1, smoothed toward `target`
    var target: Float = 0          // written from the main thread on key up/down
    var phaseStep: Double = 2 * .pi * 600 / 48_000
    var gainStep: Float = 1.0 / (0.005 * 48_000)   // 5ms to full scale
    var amplitude: Float = 0.35
}

public final class Player: ObservableObject {

    let engine = AVAudioEngine()

    private let transmission = AVAudioPlayerNode()
    private var sidetone: AVAudioSourceNode?
    private let sidetoneState = SidetoneState()

    private(set) var renderer = MorseRenderer()
    private(set) var renderFormat: AVAudioFormat

    /// Frames in the transmission currently scheduled, for end-of-playback detection.
    private(set) var scheduledFrames: Int = 0

    init() {
        // Match the hardware rate so nothing resamples underneath us — a resampler
        // between us and the device would reintroduce the timing slop we just removed.
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let rate = hardwareRate > 0 ? hardwareRate : 48_000

        renderer.sampleRate = rate
        renderFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)
            ?? engine.outputNode.outputFormat(forBus: 0)

        sidetoneState.phaseStep = 2 * .pi * renderer.frequency / rate
        sidetoneState.gainStep = 1.0 / Float(renderer.rampSeconds * rate)
        sidetoneState.amplitude = renderer.amplitude

        engine.attach(transmission)
        engine.connect(transmission, to: engine.mainMixerNode, format: renderFormat)

        let source = makeSidetoneNode(format: renderFormat)
        sidetone = source
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: renderFormat)

        start()
    }

    private func makeSidetoneNode(format: AVAudioFormat) -> AVAudioSourceNode {
        let state = sidetoneState
        return AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                // Walk the linear gain toward the target, then shape it. Shaping the
                // ramp (rather than switching amplitude outright) is what keeps the
                // key from clicking.
                if state.gain < state.target {
                    state.gain = min(state.target, state.gain + state.gainStep)
                } else if state.gain > state.target {
                    state.gain = max(state.target, state.gain - state.gainStep)
                }

                let shaped = 0.5 * (1 - cos(Double(state.gain) * Double.pi))
                let sample = Float(sin(state.phase) * shaped) * state.amplitude

                state.phase += state.phaseStep
                if state.phase > 2 * .pi { state.phase -= 2 * .pi }

                for buffer in buffers {
                    let pointer = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < pointer.count { pointer[frame] = sample }
                }
            }
            return noErr
        }
    }

    // MARK: - Engine lifecycle

    func start() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("Failed to start engine: \(error)")
        }
    }

    // MARK: - Transmissions

    /// Renders `tones` and schedules the lot in one call.
    /// - Returns: the frame layout, so a caller can follow along off the audio clock.
    @discardableResult
    func play(tones: [Tone]) -> [ToneSpan] {
        stop()
        start()

        guard let (buffer, spans) = renderer.render(tones, format: renderFormat) else {
            return []
        }

        scheduledFrames = spans.last?.endFrame ?? 0
        transmission.scheduleBuffer(buffer, at: nil, options: [])
        transmission.play()
        return spans
    }

    /// Schedules an already-rendered buffer — the mix path, where the caller has
    /// summed several voices into one buffer itself.
    func schedule(buffer: AVAudioPCMBuffer, frames: Int) {
        stop()
        start()
        scheduledFrames = frames
        transmission.scheduleBuffer(buffer, at: nil, options: [])
        transmission.play()
    }

    func stop() {
        transmission.stop()
        scheduledFrames = 0
    }

    /// Where the audio hardware actually is, in frames since this transmission started,
    /// or nil when nothing is playing. This is the clock the UI should follow.
    var currentFrame: Int? {
        guard transmission.isPlaying,
              let nodeTime = transmission.lastRenderTime,
              let playerTime = transmission.playerTime(forNodeTime: nodeTime)
        else { return nil }
        return Int(playerTime.sampleTime)
    }

    // MARK: - Keyer sidetone

    func keyDown() { sidetoneState.target = 1 }
    func keyUp()   { sidetoneState.target = 0 }

    // MARK: - Diagnostics

    func setManualRenderingBufferSize(bytes: UInt32) {
        // Buffer size is negotiated with the device; retained so the diagnostics
        // panel keeps building. Timing no longer depends on it.
    }

    /// Sweeps ditTime and reports rendered vs. ideal duration.
    ///
    /// This used to play the tones and stopwatch them, which measured the scheduler
    /// more than the audio. It now measures the frame layout that actually reaches
    /// the device, so any residual error is rounding — sub-frame, not milliseconds.
    public func diagnoseTiming(sweep: [Double]) async -> [(id: Int, ditTime: Double, expected: Double, actual: Double)] {
        sweep.map { ditTime in
            let count = 10
            let tones = (0..<count).map { _ in Tone(.dit, ditTime: ditTime) }
            let frames = renderer.totalFrames(for: tones)
            return (id: Int(ditTime * 1000),
                    ditTime: ditTime,
                    expected: Double(count) * ditTime,
                    actual: Double(frames) / renderer.sampleRate)
        }
    }
}
