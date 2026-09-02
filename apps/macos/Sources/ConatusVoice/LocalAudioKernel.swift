// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum LocalAudioError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidChunk
    case sampleRateChanged
    case discontinuousAudio
    case invalidRange
    case invalidState
    case invalidScore
    case outOfOrderScore
}

public struct AudioFrameRange: Equatable, Sendable {
    public let start: Int64
    public let end: Int64

    public init(start: Int64, end: Int64) throws {
        guard start >= 0, end > start else { throw LocalAudioError.invalidRange }
        self.start = start
        self.end = end
    }

    public var count: Int64 { end - start }
}

public struct AudioChunk: Equatable, Sendable {
    public let startFrame: Int64
    public let sampleRate: Int
    public let samples: [Float]

    public init(startFrame: Int64, sampleRate: Int, samples: [Float]) throws {
        guard
            startFrame >= 0,
            sampleRate > 0,
            !samples.isEmpty,
            samples.allSatisfy(\.isFinite),
            Int64(samples.count) <= Int64.max - startFrame
        else {
            throw LocalAudioError.invalidChunk
        }
        self.startFrame = startFrame
        self.sampleRate = sampleRate
        self.samples = samples
    }

    public var endFrame: Int64 { startFrame + Int64(samples.count) }
}

public struct RollingAudioBuffer: Sendable {
    public let sampleRate: Int
    public let capacityFrames: Int

    private var storage: [Float] = []
    private var storageOffset = 0
    public private(set) var startFrame: Int64?

    public init(sampleRate: Int, capacityFrames: Int) throws {
        guard sampleRate > 0, capacityFrames > 0 else { throw LocalAudioError.invalidConfiguration }
        self.sampleRate = sampleRate
        self.capacityFrames = capacityFrames
    }

    public var endFrame: Int64? {
        startFrame.map { $0 + Int64(bufferedFrames) }
    }

    public var bufferedFrames: Int { storage.count - storageOffset }

    public mutating func append(_ chunk: AudioChunk) throws {
        guard chunk.sampleRate == sampleRate else { throw LocalAudioError.sampleRateChanged }
        if let endFrame {
            guard chunk.startFrame == endFrame else { throw LocalAudioError.discontinuousAudio }
        } else {
            startFrame = chunk.startFrame
        }

        storage.append(contentsOf: chunk.samples)
        let overflow = bufferedFrames - capacityFrames
        if overflow > 0 {
            storageOffset += overflow
            startFrame = (startFrame ?? chunk.startFrame) + Int64(overflow)
            if storageOffset >= capacityFrames || storageOffset * 2 >= storage.count {
                storage.removeFirst(storageOffset)
                storageOffset = 0
            }
        }
    }

    public func samples(in range: AudioFrameRange) throws -> [Float] {
        guard
            let startFrame,
            let endFrame,
            range.start >= startFrame,
            range.end <= endFrame
        else {
            throw LocalAudioError.invalidRange
        }
        let lower = storageOffset + Int(range.start - startFrame)
        let upper = storageOffset + Int(range.end - startFrame)
        return Array(storage[lower..<upper])
    }
}

public struct WakeScoreObservation: Equatable, Sendable {
    public let score: Double
    public let range: AudioFrameRange

    public init(score: Double, range: AudioFrameRange) throws {
        guard score.isFinite, (0 ... 1).contains(score) else { throw LocalAudioError.invalidScore }
        self.score = score
        self.range = range
    }
}

public struct WakeScoreGate: Sendable {
    public let threshold: Double
    public let requiredConsecutiveHits: Int
    public let cooldownFrames: Int64

    private var consecutiveHits = 0
    private var candidateStart: Int64?
    private var cooldownEnd: Int64 = 0
    private var lastRangeStart: Int64?
    private var lastRangeEnd: Int64?

    public init(threshold: Double, requiredConsecutiveHits: Int, cooldownFrames: Int64) throws {
        guard
            threshold.isFinite,
            (0 ... 1).contains(threshold),
            requiredConsecutiveHits > 0,
            cooldownFrames >= 0
        else {
            throw LocalAudioError.invalidConfiguration
        }
        self.threshold = threshold
        self.requiredConsecutiveHits = requiredConsecutiveHits
        self.cooldownFrames = cooldownFrames
    }

    public mutating func observe(_ observation: WakeScoreObservation) throws -> AudioFrameRange? {
        if let lastRangeStart, observation.range.start < lastRangeStart {
            throw LocalAudioError.outOfOrderScore
        }
        if let lastRangeEnd, observation.range.end <= lastRangeEnd {
            throw LocalAudioError.outOfOrderScore
        }
        if let lastRangeEnd, observation.range.start > lastRangeEnd {
            resetCandidate()
        }
        lastRangeStart = observation.range.start
        lastRangeEnd = observation.range.end

        guard observation.range.start >= cooldownEnd else {
            resetCandidate()
            return nil
        }
        guard observation.score >= threshold else {
            resetCandidate()
            return nil
        }

        if consecutiveHits == 0 {
            candidateStart = observation.range.start
        }
        consecutiveHits += 1
        guard consecutiveHits >= requiredConsecutiveHits, let candidateStart else { return nil }

        let activation = try AudioFrameRange(start: candidateStart, end: observation.range.end)
        guard observation.range.end <= Int64.max - cooldownFrames else {
            throw LocalAudioError.invalidRange
        }
        cooldownEnd = observation.range.end + cooldownFrames
        resetCandidate()
        return activation
    }

    private mutating func resetCandidate() {
        consecutiveHits = 0
        candidateStart = nil
    }
}

public enum TurnEndReason: Equatable, Sendable {
    case trailingSilence
    case maximumDuration
}

public struct TurnEnd: Equatable, Sendable {
    public let endFrame: Int64
    public let reason: TurnEndReason
}

public struct EnergyTurnEndDetector: Sendable {
    public let startFrame: Int64
    public let sampleRate: Int
    public let energyThreshold: Double
    public let minimumSpeechFrames: Int64
    public let trailingSilenceFrames: Int64
    public let maximumTurnFrames: Int64

    private var nextFrame: Int64
    private var speechFrames: Int64 = 0
    private var lastSpeechEnd: Int64?
    private var silenceFrames: Int64 = 0
    private var completed = false

    public init(
        startFrame: Int64,
        sampleRate: Int,
        energyThreshold: Double,
        minimumSpeechFrames: Int64,
        trailingSilenceFrames: Int64,
        maximumTurnFrames: Int64
    ) throws {
        guard
            startFrame >= 0,
            sampleRate > 0,
            energyThreshold.isFinite,
            energyThreshold > 0,
            minimumSpeechFrames > 0,
            trailingSilenceFrames > 0,
            maximumTurnFrames > minimumSpeechFrames + trailingSilenceFrames
        else {
            throw LocalAudioError.invalidConfiguration
        }
        self.startFrame = startFrame
        self.sampleRate = sampleRate
        self.energyThreshold = energyThreshold
        self.minimumSpeechFrames = minimumSpeechFrames
        self.trailingSilenceFrames = trailingSilenceFrames
        self.maximumTurnFrames = maximumTurnFrames
        nextFrame = startFrame
    }

    public mutating func observe(_ chunk: AudioChunk) throws -> TurnEnd? {
        guard !completed else { throw LocalAudioError.invalidState }
        guard chunk.sampleRate == sampleRate else { throw LocalAudioError.sampleRateChanged }
        guard chunk.startFrame == nextFrame else { throw LocalAudioError.discontinuousAudio }
        nextFrame = chunk.endFrame

        let meanSquare = chunk.samples.reduce(0.0) { partial, sample in
            partial + Double(sample) * Double(sample)
        } / Double(chunk.samples.count)
        if meanSquare.squareRoot() >= energyThreshold {
            speechFrames += Int64(chunk.samples.count)
            lastSpeechEnd = chunk.endFrame
            silenceFrames = 0
            return completeAtMaximumIfNeeded(currentEnd: chunk.endFrame)
        }

        guard speechFrames >= minimumSpeechFrames else {
            return completeAtMaximumIfNeeded(currentEnd: chunk.endFrame)
        }
        silenceFrames += Int64(chunk.samples.count)
        if silenceFrames >= trailingSilenceFrames, let lastSpeechEnd {
            completed = true
            return TurnEnd(endFrame: lastSpeechEnd, reason: .trailingSilence)
        }
        return completeAtMaximumIfNeeded(currentEnd: chunk.endFrame)
    }

    private mutating func completeAtMaximumIfNeeded(currentEnd: Int64) -> TurnEnd? {
        if currentEnd - startFrame >= maximumTurnFrames {
            completed = true
            return TurnEnd(endFrame: startFrame + maximumTurnFrames, reason: .maximumDuration)
        }
        return nil
    }
}

public enum ActivatedTurnCaptureState: String, Codable, Sendable {
    case awaitingWake = "awaiting_wake"
    case capturing
    case completed
}

public struct CapturedAudioTurn: Equatable, Sendable {
    public let turnID: VoiceTurnID
    public let sampleRate: Int
    public let activationRange: AudioFrameRange
    public let endFrame: Int64
    public let samples: [Float]

    public init(
        turnID: VoiceTurnID,
        sampleRate: Int,
        activationRange: AudioFrameRange,
        endFrame: Int64,
        samples: [Float]
    ) {
        self.turnID = turnID
        self.sampleRate = sampleRate
        self.activationRange = activationRange
        self.endFrame = endFrame
        self.samples = samples
    }
}

public enum LocalAudioAction: Equatable, Sendable {
    case playAcknowledgement
    case showListening
    case turnCompleted(CapturedAudioTurn)
}

public struct LocalAudioDiagnostics: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let state: ActivatedTurnCaptureState
    public let bufferedFrames: Int
    public let capturedFrames: Int
}

public struct ActivatedTurnCapture: Sendable {
    public let sampleRate: Int
    public let rollingCapacityFrames: Int
    public let maximumTurnFrames: Int

    public private(set) var state: ActivatedTurnCaptureState = .awaitingWake
    private var rollingBuffer: RollingAudioBuffer
    private var turnBuffer: RollingAudioBuffer?
    private var turnID: VoiceTurnID?
    private var activationRange: AudioFrameRange?

    public init(sampleRate: Int, rollingCapacityFrames: Int, maximumTurnFrames: Int) throws {
        guard maximumTurnFrames > rollingCapacityFrames else { throw LocalAudioError.invalidConfiguration }
        self.sampleRate = sampleRate
        self.rollingCapacityFrames = rollingCapacityFrames
        self.maximumTurnFrames = maximumTurnFrames
        rollingBuffer = try RollingAudioBuffer(sampleRate: sampleRate, capacityFrames: rollingCapacityFrames)
    }

    public var diagnostics: LocalAudioDiagnostics {
        let capturedFrames: Int
        if let activationRange, let endFrame = turnBuffer?.endFrame {
            capturedFrames = max(0, Int(endFrame - activationRange.start))
        } else {
            capturedFrames = 0
        }
        return LocalAudioDiagnostics(
            schemaVersion: 1,
            state: state,
            bufferedFrames: state == .awaitingWake
                ? rollingBuffer.bufferedFrames
                : (turnBuffer?.bufferedFrames ?? 0),
            capturedFrames: capturedFrames
        )
    }

    public mutating func append(_ chunk: AudioChunk) throws -> [LocalAudioAction] {
        guard state != .completed else { throw LocalAudioError.invalidState }
        if state == .awaitingWake {
            try rollingBuffer.append(chunk)
            return []
        }
        guard
            let activationRange,
            var activeBuffer = turnBuffer,
            let activeEnd = activeBuffer.endFrame
        else {
            throw LocalAudioError.invalidState
        }
        let remaining = Int64(maximumTurnFrames) - (activeEnd - activationRange.start)
        guard remaining > 0 else { throw LocalAudioError.invalidState }
        if Int64(chunk.samples.count) >= remaining {
            let limited = try AudioChunk(
                startFrame: chunk.startFrame,
                sampleRate: chunk.sampleRate,
                samples: Array(chunk.samples.prefix(Int(remaining)))
            )
            try activeBuffer.append(limited)
            turnBuffer = activeBuffer
            return [try complete(at: activationRange.start + Int64(maximumTurnFrames))]
        }
        try activeBuffer.append(chunk)
        turnBuffer = activeBuffer
        return []
    }

    public mutating func activate(turnID: VoiceTurnID, range: AudioFrameRange) throws -> [LocalAudioAction] {
        guard state == .awaitingWake else { throw LocalAudioError.invalidState }
        guard let rollingEnd = rollingBuffer.endFrame else { throw LocalAudioError.invalidRange }
        _ = try rollingBuffer.samples(in: range)
        let retainedRange = try AudioFrameRange(start: range.start, end: rollingEnd)
        let retainedSamples = try rollingBuffer.samples(in: retainedRange)
        var activeBuffer = try RollingAudioBuffer(sampleRate: sampleRate, capacityFrames: maximumTurnFrames)
        try activeBuffer.append(
            AudioChunk(startFrame: range.start, sampleRate: sampleRate, samples: retainedSamples)
        )
        self.turnID = turnID
        activationRange = range
        turnBuffer = activeBuffer
        state = .capturing
        return [.playAcknowledgement, .showListening]
    }

    public mutating func finish(at endFrame: Int64) throws -> LocalAudioAction {
        try complete(at: endFrame)
    }

    private mutating func complete(at endFrame: Int64) throws -> LocalAudioAction {
        guard
            state == .capturing,
            let turnID,
            let activationRange,
            let turnBuffer,
            endFrame > activationRange.end
        else {
            throw LocalAudioError.invalidState
        }
        let range = try AudioFrameRange(start: activationRange.start, end: endFrame)
        let samples = try turnBuffer.samples(in: range)
        state = .completed
        return .turnCompleted(
            CapturedAudioTurn(
                turnID: turnID,
                sampleRate: sampleRate,
                activationRange: activationRange,
                endFrame: endFrame,
                samples: samples
            )
        )
    }
}
