// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import ConatusVoice
import Testing
@testable import ConatusVoicePlatform

@Suite("Native microphone boundary")
struct MacMicrophoneSourceTests {
    @Test("deep copies PCM and exposes only the first channel")
    func copiesFirstChannel() throws {
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 2,
            interleaved: false
        ))
        let source = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        source.frameLength = 4
        let channels = try #require(source.floatChannelData)
        for index in 0 ..< 4 {
            channels[0][index] = Float(index + 1)
            channels[1][index] = Float(index + 9)
        }

        let frame = try CopiedMicrophoneFrame(buffer: source, startFrame: 10)
        channels[0][0] = 99

        #expect(frame.audioChunk.startFrame == 10)
        #expect(frame.audioChunk.endFrame == 14)
        #expect(frame.audioChunk.sampleRate == 16_000)
        #expect(frame.audioChunk.samples == [1, 2, 3, 4])
        #expect(frame.pcmBuffer.floatChannelData?[0][0] == 1)
        #expect(frame.pcmBuffer.floatChannelData?[1][0] == 9)
    }

    @Test("assigns monotonically increasing frame positions and resets explicitly")
    func frameClockIsMonotonic() {
        let clock = MonotonicAudioFrameClock()
        #expect(clock.take(frameCount: 2_048) == 0)
        #expect(clock.take(frameCount: 512) == 2_048)
        #expect(clock.take(frameCount: 0) == nil)
        clock.reset()
        #expect(clock.take(frameCount: 1) == 0)
    }

    @Test("permission denial stops before microphone input access")
    @MainActor
    func deniedPermissionDoesNotStartEngine() throws {
        let source = MacMicrophoneSource(
            engine: AVAudioEngine(),
            authorizationProvider: { .denied }
        )

        #expect(throws: MacMicrophoneSourceError.permissionRequired(.denied)) {
            try source.start { _ in }
        }
        #expect(!source.isRunning)
        source.stop()
    }
}
