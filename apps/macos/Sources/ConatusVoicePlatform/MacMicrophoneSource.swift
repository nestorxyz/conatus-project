// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import ConatusVoice
import Foundation

public enum MicrophoneAuthorization: String, Sendable {
    case notDetermined = "not_determined"
    case denied
    case restricted
    case authorized
}

public enum MacMicrophoneSourceError: Error, Equatable, Sendable {
    case permissionRequired(MicrophoneAuthorization)
    case alreadyRunning
    case unavailableInput
    case unsupportedFormat
    case bufferCopyFailed
    case engineStartFailed
}

public final class CopiedMicrophoneFrame: @unchecked Sendable {
    public let audioChunk: AudioChunk
    let pcmBuffer: AVAudioPCMBuffer

    init(buffer: AVAudioPCMBuffer, startFrame: Int64) throws {
        let format = buffer.format
        guard
            format.commonFormat == .pcmFormatFloat32,
            !format.isInterleaved,
            format.channelCount > 0,
            format.sampleRate > 0,
            buffer.frameLength > 0,
            let sourceChannels = buffer.floatChannelData,
            let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
            let destinationChannels = copy.floatChannelData
        else {
            throw MacMicrophoneSourceError.unsupportedFormat
        }

        copy.frameLength = buffer.frameLength
        let frameCount = Int(buffer.frameLength)
        for channel in 0 ..< Int(format.channelCount) {
            destinationChannels[channel].update(from: sourceChannels[channel], count: frameCount)
        }
        let roundedSampleRate = Int(format.sampleRate.rounded())
        guard abs(format.sampleRate - Double(roundedSampleRate)) < 0.001 else {
            throw MacMicrophoneSourceError.unsupportedFormat
        }
        pcmBuffer = copy
        audioChunk = try AudioChunk(
            startFrame: startFrame,
            sampleRate: roundedSampleRate,
            samples: Array(UnsafeBufferPointer(start: destinationChannels[0], count: frameCount))
        )
    }
}

final class MonotonicAudioFrameClock: @unchecked Sendable {
    private let lock = NSLock()
    private var nextFrame: Int64 = 0

    func take(frameCount: Int) -> Int64? {
        lock.lock()
        defer { lock.unlock() }
        guard frameCount > 0, Int64(frameCount) <= Int64.max - nextFrame else { return nil }
        let start = nextFrame
        nextFrame += Int64(frameCount)
        return start
    }

    func reset() {
        lock.lock()
        nextFrame = 0
        lock.unlock()
    }
}

@MainActor
public final class MacMicrophoneSource {
    public typealias FrameHandler = @Sendable (Result<CopiedMicrophoneFrame, MacMicrophoneSourceError>) -> Void

    private let engine: AVAudioEngine
    private let authorizationProvider: @MainActor @Sendable () -> MicrophoneAuthorization
    private let clock = MonotonicAudioFrameClock()
    private var tapInstalled = false

    public init() {
        engine = AVAudioEngine()
        authorizationProvider = { Self.systemAuthorization }
    }

    init(
        engine: AVAudioEngine,
        authorizationProvider: @escaping @MainActor @Sendable () -> MicrophoneAuthorization
    ) {
        self.engine = engine
        self.authorizationProvider = authorizationProvider
    }

    public nonisolated static var systemAuthorization: MicrophoneAuthorization {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        case .authorized: .authorized
        @unknown default: .denied
        }
    }

    public static func requestAuthorization() async -> MicrophoneAuthorization {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                continuation.resume(returning: systemAuthorization)
            }
        }
    }

    public var isRunning: Bool { engine.isRunning }

    public func start(handler: @escaping FrameHandler) throws {
        let authorization = authorizationProvider()
        guard authorization == .authorized else {
            throw MacMicrophoneSourceError.permissionRequired(authorization)
        }
        guard !engine.isRunning, !tapInstalled else { throw MacMicrophoneSourceError.alreadyRunning }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MacMicrophoneSourceError.unavailableInput
        }
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
            throw MacMicrophoneSourceError.unsupportedFormat
        }

        clock.reset()
        input.installTap(onBus: 0, bufferSize: 2_048, format: format) { [clock] buffer, _ in
            guard let startFrame = clock.take(frameCount: Int(buffer.frameLength)) else {
                handler(.failure(.bufferCopyFailed))
                return
            }
            do {
                handler(.success(try CopiedMicrophoneFrame(buffer: buffer, startFrame: startFrame)))
            } catch let error as MacMicrophoneSourceError {
                handler(.failure(error))
            } catch {
                handler(.failure(.bufferCopyFailed))
            }
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            throw MacMicrophoneSourceError.engineStartFailed
        }
    }

    public func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        clock.reset()
    }
}
