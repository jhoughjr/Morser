//
//  MorserXTests.swift
//  MorserXTests
//
//  Created by Jimmy Hough Jr on 12/13/24.
//

import Testing
import AVFoundation
import Morse
@testable import MorserX

/// These pin the property the old Task.sleep playback could not hold: that a dit,
/// a dah and the gaps between them keep their 1:3:1 relationship at every speed.
/// The renderer is pure, so this runs without audio hardware.
struct MorseTimingTests {

    let renderer = MorseRenderer(sampleRate: 48_000)

    // MARK: - Ratios

    @Test("dit:dah:gap holds 1:3:1 in frames, at every speed",
          arguments: [0.2, 0.1, 0.06, 0.03, 0.012, 0.002])
    func ratiosExact(ditTime: Double) {
        let tones = [Tone(.dit, ditTime: ditTime),
                     Tone(.infraSpace, ditTime: ditTime),
                     Tone(.dah, ditTime: ditTime),
                     Tone(.letterSpace, ditTime: ditTime),
                     Tone(.wordSpace, ditTime: ditTime)]

        let spans = renderer.spans(for: tones)
        let dit = Double(spans[0].frameCount)

        // A frame at 48kHz is ~21µs; a boundary can round by one, no more.
        #expect(abs(Double(spans[1].frameCount) - dit) <= 1)        // infra space == 1 dit
        #expect(abs(Double(spans[2].frameCount) - dit * 3) <= 1)    // dah == 3 dits
        #expect(abs(Double(spans[3].frameCount) - dit * 3) <= 1)    // letter space == 3 dits
        #expect(abs(Double(spans[4].frameCount) - dit * 7) <= 1)    // word space == 7 dits
    }

    // MARK: - Drift

    @Test("500 elements accumulate no timing drift")
    func noCumulativeDrift() {
        let ditTime = 0.03
        let tones = (0..<500).map { _ in Tone(.dit, ditTime: ditTime) }

        let expected = Double(tones.count) * ditTime
        let actual = Double(renderer.totalFrames(for: tones)) / renderer.sampleRate

        // The sleep-based player overshot this by ~38% per element. Anything above
        // a frame of total error here means boundaries are compounding again.
        #expect(abs(actual - expected) < 1.0 / renderer.sampleRate)
    }

    @Test("element boundaries stay locked to the ideal grid")
    func boundariesOnGrid() {
        let ditTime = 0.06
        let tones = (0..<200).map { i in Tone(i.isMultiple(of: 2) ? .dit : .dah, ditTime: ditTime) }
        let spans = renderer.spans(for: tones)

        var ideal = 0.0
        for span in spans {
            #expect(abs(Double(span.startFrame) - ideal * renderer.sampleRate) <= 1)
            ideal += tones[span.id].duration
        }
    }

    // MARK: - Envelope

    @Test("sounding elements ramp from and return to silence")
    func envelopeIsClickFree() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let tones = [Tone(.dah, ditTime: 0.06)]
        let rendered = try #require(renderer.render(tones, format: format))
        let samples = try #require(rendered.buffer.floatChannelData)[0]

        let span = rendered.spans[0]
        // A hard gate would start at full amplitude; a raised cosine starts at zero.
        #expect(abs(samples[span.startFrame]) < 0.001)
        #expect(abs(samples[span.endFrame - 1]) < 0.001)

        var peak: Float = 0
        for i in span.startFrame..<span.endFrame { peak = max(peak, abs(samples[i])) }
        #expect(peak > 0.3)   // reaches full scale in the middle
    }

    @Test("spaces render as actual silence")
    func spacesAreSilent() throws {
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let tones = [Tone(.dit, ditTime: 0.06), Tone(.wordSpace, ditTime: 0.06)]
        let rendered = try #require(renderer.render(tones, format: format))
        let samples = try #require(rendered.buffer.floatChannelData)[0]

        for i in rendered.spans[1].startFrame..<rendered.spans[1].endFrame {
            #expect(samples[i] == 0)
        }
    }
}
