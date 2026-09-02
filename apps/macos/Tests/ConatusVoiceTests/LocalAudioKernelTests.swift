// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import ConatusVoice

final class LocalAudioKernelTests: XCTestCase {
    func testRollingBufferIsBoundedAndRejectsDiscontinuity() throws {
        var buffer = try RollingAudioBuffer(sampleRate: 16_000, capacityFrames: 5)
        try buffer.append(chunk(start: 0, samples: [0, 1, 2, 3]))
        try buffer.append(chunk(start: 4, samples: [4, 5, 6]))

        XCTAssertEqual(buffer.startFrame, 2)
        XCTAssertEqual(buffer.bufferedFrames, 5)
        XCTAssertEqual(try buffer.samples(in: range(2, 7)), [2, 3, 4, 5, 6])
        XCTAssertThrowsError(try buffer.append(chunk(start: 8, samples: [8])))
        XCTAssertThrowsError(try buffer.append(AudioChunk(startFrame: 7, sampleRate: 24_000, samples: [7])))
    }

    func testActivatedTurnExcludesAmbientFramesBeforeWakeRange() throws {
        var capture = try ActivatedTurnCapture(
            sampleRate: 16_000,
            rollingCapacityFrames: 8,
            maximumTurnFrames: 12
        )
        _ = try capture.append(chunk(start: 0, samples: [0, 1, 2, 3, 4, 5, 6, 7]))
        let turnID = try XCTUnwrap(VoiceTurnID("turn-1"))

        XCTAssertEqual(
            try capture.activate(turnID: turnID, range: range(4, 8)),
            [.playAcknowledgement, .showListening]
        )
        _ = try capture.append(chunk(start: 8, samples: [8, 9, 10, 11]))

        guard case .turnCompleted(let turn) = try capture.finish(at: 12) else {
            return XCTFail("expected a completed activated turn")
        }
        XCTAssertEqual(turn.activationRange, try range(4, 8))
        XCTAssertEqual(turn.samples, [4, 5, 6, 7, 8, 9, 10, 11])
        XCTAssertFalse(turn.samples.contains(0))
        XCTAssertEqual(capture.state, .completed)
    }

    func testActivationMustBeInsideRetainedAudio() throws {
        var capture = try ActivatedTurnCapture(
            sampleRate: 16_000,
            rollingCapacityFrames: 4,
            maximumTurnFrames: 5
        )
        _ = try capture.append(chunk(start: 0, samples: [0, 1, 2, 3, 4, 5]))
        let turnID = try XCTUnwrap(VoiceTurnID("turn-1"))
        XCTAssertThrowsError(try capture.activate(turnID: turnID, range: range(0, 2)))
    }

    func testCaptureCompletesAtMaximumWithoutRetainingOverflow() throws {
        var capture = try ActivatedTurnCapture(
            sampleRate: 16_000,
            rollingCapacityFrames: 4,
            maximumTurnFrames: 6
        )
        _ = try capture.append(chunk(start: 0, samples: [0, 1, 2, 3]))
        let turnID = try XCTUnwrap(VoiceTurnID("turn-1"))
        _ = try capture.activate(turnID: turnID, range: range(2, 4))

        let actions = try capture.append(chunk(start: 4, samples: [4, 5, 6, 7, 8, 9]))
        guard case .turnCompleted(let turn) = try XCTUnwrap(actions.first) else {
            return XCTFail("expected maximum-duration completion")
        }
        XCTAssertEqual(turn.endFrame, 8)
        XCTAssertEqual(turn.samples, [2, 3, 4, 5, 6, 7])
        XCTAssertEqual(capture.state, .completed)
    }

    func testWakeScoreGateRequiresConsecutiveHitsAndAppliesCooldown() throws {
        var gate = try WakeScoreGate(threshold: 0.8, requiredConsecutiveHits: 2, cooldownFrames: 10)
        XCTAssertNil(try gate.observe(score(0.9, 0, 4)))
        XCTAssertEqual(try gate.observe(score(0.85, 2, 6)), try range(0, 6))
        XCTAssertNil(try gate.observe(score(0.95, 6, 9)))
        XCTAssertNil(try gate.observe(score(0.95, 12, 17)))
        XCTAssertNil(try gate.observe(score(0.95, 16, 20)))
        XCTAssertEqual(try gate.observe(score(0.95, 18, 22)), try range(16, 22))
        XCTAssertThrowsError(try gate.observe(score(0.9, 17, 23)))
    }

    func testWakeScoreGateRejectsReplayedWindow() throws {
        var gate = try WakeScoreGate(threshold: 0.8, requiredConsecutiveHits: 2, cooldownFrames: 0)
        XCTAssertNil(try gate.observe(score(0.9, 0, 4)))
        XCTAssertThrowsError(try gate.observe(score(0.9, 0, 4)))
    }

    func testWakeScoreGapResetsCandidateAndMalformedScoreFails() throws {
        var gate = try WakeScoreGate(threshold: 0.8, requiredConsecutiveHits: 2, cooldownFrames: 0)
        XCTAssertNil(try gate.observe(score(0.9, 0, 4)))
        XCTAssertNil(try gate.observe(score(0.9, 6, 10)))
        XCTAssertEqual(try gate.observe(score(0.9, 8, 12)), try range(6, 12))
        XCTAssertThrowsError(try WakeScoreObservation(score: .nan, range: range(12, 14)))
    }

    func testTurnEndRequiresSpeechThenTrailingSilence() throws {
        var detector = try EnergyTurnEndDetector(
            startFrame: 10,
            sampleRate: 16_000,
            energyThreshold: 0.1,
            minimumSpeechFrames: 4,
            trailingSilenceFrames: 4,
            maximumTurnFrames: 20
        )
        XCTAssertNil(try detector.observe(chunk(start: 10, samples: [0, 0])))
        XCTAssertNil(try detector.observe(chunk(start: 12, samples: [0.5, 0.5, 0.5, 0.5])))
        XCTAssertNil(try detector.observe(chunk(start: 16, samples: [0, 0])))
        XCTAssertEqual(
            try detector.observe(chunk(start: 18, samples: [0, 0])),
            TurnEnd(endFrame: 16, reason: .trailingSilence)
        )
    }

    func testTurnEndEnforcesMaximumDuration() throws {
        var detector = try EnergyTurnEndDetector(
            startFrame: 0,
            sampleRate: 16_000,
            energyThreshold: 0.1,
            minimumSpeechFrames: 2,
            trailingSilenceFrames: 2,
            maximumTurnFrames: 6
        )
        XCTAssertThrowsError(
            try detector.observe(AudioChunk(startFrame: 0, sampleRate: 24_000, samples: [0.5, 0.5]))
        )
        XCTAssertNil(try detector.observe(chunk(start: 0, samples: [0.5, 0.5, 0.5])))
        XCTAssertEqual(
            try detector.observe(chunk(start: 3, samples: [0.5, 0.5, 0.5])),
            TurnEnd(endFrame: 6, reason: .maximumDuration)
        )
    }

    func testTrailingSilenceWinsWhenChunkAlsoReachesMaximum() throws {
        var detector = try EnergyTurnEndDetector(
            startFrame: 0,
            sampleRate: 16_000,
            energyThreshold: 0.1,
            minimumSpeechFrames: 2,
            trailingSilenceFrames: 4,
            maximumTurnFrames: 8
        )
        XCTAssertNil(try detector.observe(chunk(start: 0, samples: [0.5, 0.5, 0.5, 0.5])))
        XCTAssertNil(try detector.observe(chunk(start: 4, samples: [0, 0])))
        XCTAssertEqual(
            try detector.observe(chunk(start: 6, samples: [0, 0])),
            TurnEnd(endFrame: 4, reason: .trailingSilence)
        )
    }

    func testDiagnosticsContainNoSamplesOrPrivateVoiceData() throws {
        var capture = try ActivatedTurnCapture(
            sampleRate: 16_000,
            rollingCapacityFrames: 4,
            maximumTurnFrames: 8
        )
        _ = try capture.append(chunk(start: 0, samples: [0.25, 0.5]))
        let encoded = try JSONEncoder().encode(capture.diagnostics)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for forbidden in ["sample", "audio", "transcript", "provider", "credential", "path", "codex"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
    }

    private func chunk(start: Int64, samples: [Float]) throws -> AudioChunk {
        try AudioChunk(startFrame: start, sampleRate: 16_000, samples: samples)
    }

    private func range(_ start: Int64, _ end: Int64) throws -> AudioFrameRange {
        try AudioFrameRange(start: start, end: end)
    }

    private func score(_ value: Double, _ start: Int64, _ end: Int64) throws -> WakeScoreObservation {
        try WakeScoreObservation(score: value, range: range(start, end))
    }
}
