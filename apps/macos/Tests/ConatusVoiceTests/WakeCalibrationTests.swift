// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import ConatusVoice

@Suite("Local wake calibration")
struct WakeCalibrationTests {
    @Test("passes at the lowest threshold satisfying both gates and deletes every capture")
    func passesDeterministically() throws {
        var calibration = fixture()
        #expect(try calibration.start(now: validNow) == [.disableWake])

        var effects: [WakeCalibrationEffect] = []
        for (index, score) in [0.82, 0.76, 0.71].enumerated() {
            effects += try calibration.submit(trial("p\(index)", .positive, score))
        }
        for (index, score) in [0.18, 0.31, 0.54].enumerated() {
            effects += try calibration.submit(trial("n\(index)", .hardNegative, score))
        }

        #expect(effects.filter(isDeletion).count == 6)
        #expect(effects.last == .enableWake(threshold: 0.55))
        #expect(calibration.state == .passed(
            threshold: 0.55,
            deviceID: "device-hash-1",
            modelSHA256: String(repeating: "a", count: 64),
            policyRevision: "policy-v1"
        ))
    }

    @Test("failed scores keep wake disabled and expose manual activation")
    func failsClosed() throws {
        var calibration = fixture()
        _ = try calibration.start(now: validNow)
        for index in 0 ..< 3 {
            _ = try calibration.submit(trial("p\(index)", .positive, 0.3))
        }
        var finalEffects: [WakeCalibrationEffect] = []
        for index in 0 ..< 3 {
            finalEffects = try calibration.submit(trial("n\(index)", .hardNegative, 0.8))
        }

        #expect(calibration.state == .failed(.scoreGateFailed))
        #expect(finalEffects == [
            .deleteRawAudio(ephemeralCaptureID: "n2"), .disableWake, .showManualFallback,
        ])
    }

    @Test("retry is deterministic and cannot switch devices")
    func retryAndDeviceMismatch() throws {
        var calibration = fixture()
        _ = try calibration.start(now: Date(timeIntervalSince1970: 1_900_000_000))
        #expect(calibration.state == .manualFallback(.stalePolicy))

        let otherDevice = WakeCalibrationDevice(
            opaqueDeviceID: "device-hash-2",
            architecture: "arm64",
            macOSMajorVersion: 14,
            microphoneClass: "built_in"
        )
        let effects = try calibration.retry(now: validNow, device: otherDevice)
        #expect(calibration.state == .manualFallback(.deviceMismatch))
        #expect(effects == [.disableWake, .showManualFallback])
    }

    @Test("same-device retry can recover after a stale failure")
    func retryRecovers() throws {
        var calibration = fixture()
        _ = try calibration.start(now: Date(timeIntervalSince1970: 1_900_000_000))
        let effects = try calibration.retry(now: validNow, device: supportedDevice)
        #expect(effects == [.disableWake])
        #expect(calibration.state == .collectingPositive(completed: 0, required: 3))
    }

    @Test("stored calibration is rejected when stale or bound to another device")
    func rejectsStoredCalibrationDrift() throws {
        let receipt = WakeCalibrationReceipt(
            threshold: 0.55,
            opaqueDeviceID: "another-device",
            modelSHA256: String(repeating: "a", count: 64),
            policyRevision: "policy-v1"
        )
        var mismatched = fixture()
        #expect(try mismatched.restore(receipt, now: validNow) == [.disableWake, .showManualFallback])
        #expect(mismatched.state == .manualFallback(.deviceMismatch))

        var stale = fixture()
        #expect(try stale.restore(receipt, now: Date(timeIntervalSince1970: 1_900_000_000))
            == [.disableWake, .showManualFallback])
        #expect(stale.state == .manualFallback(.stalePolicy))

        let wrongPolicy = WakeCalibrationReceipt(
            threshold: 0.55,
            opaqueDeviceID: "device-hash-1",
            modelSHA256: String(repeating: "a", count: 64),
            policyRevision: "another-policy"
        )
        var drifted = fixture()
        #expect(try drifted.restore(wrongPolicy, now: validNow) == [.disableWake, .showManualFallback])
        #expect(drifted.state == .manualFallback(.receiptMismatch))
    }

    @Test("unsupported hardware never begins capture")
    func rejectsUnsupportedDevice() throws {
        let unsupported = WakeCalibrationDevice(
            opaqueDeviceID: "device-hash-x",
            architecture: "x86_64",
            macOSMajorVersion: 14,
            microphoneClass: "built_in"
        )
        var calibration = fixture(device: unsupported)
        #expect(try calibration.start(now: validNow) == [.disableWake, .showManualFallback])
        #expect(calibration.state == .manualFallback(.unsupportedDevice))
    }

    @Test("out-of-sequence evidence is deleted and fails closed")
    func rejectsUnexpectedTrial() throws {
        var calibration = fixture()
        _ = try calibration.start(now: validNow)
        #expect(try calibration.submit(trial("not-stored", .hardNegative, 0.2)) == [
            .deleteRawAudio(ephemeralCaptureID: "not-stored"), .disableWake, .showManualFallback,
        ])
        #expect(calibration.state == .failed(.invalidContract))
    }

    @Test("invalid score evidence is deleted before calibration fails")
    func deletesInvalidScoreEvidence() throws {
        var calibration = fixture()
        _ = try calibration.start(now: validNow)
        #expect(try calibration.submit(trial("invalid-score", .positive, .nan)) == [
            .deleteRawAudio(ephemeralCaptureID: "invalid-score"), .disableWake, .showManualFallback,
        ])
        #expect(calibration.state == .failed(.invalidContract))
    }

    private let validNow = Date(timeIntervalSince1970: 1_800_000_000)
    private let supportedDevice = WakeCalibrationDevice(
        opaqueDeviceID: "device-hash-1",
        architecture: "arm64",
        macOSMajorVersion: 14,
        microphoneClass: "built_in"
    )

    private func fixture(device: WakeCalibrationDevice? = nil) -> LocalWakeCalibration {
        LocalWakeCalibration(
            contract: WakeCalibrationContract(
                modelSHA256: String(repeating: "a", count: 64),
                policyRevision: "policy-v1",
                expiresAt: Date(timeIntervalSince1970: 1_850_000_000),
                supportedArchitecture: "arm64",
                minimumMacOSMajorVersion: 14,
                supportedMicrophoneClass: "built_in",
                positiveTrialCount: 3,
                hardNegativeTrialCount: 3,
                maximumFalseRejects: 0,
                maximumFalseAccepts: 0,
                thresholdCandidates: [0.55, 0.65, 0.75]
            ),
            device: device ?? supportedDevice
        )
    }

    private func trial(
        _ id: String,
        _ kind: WakeCalibrationTrialKind,
        _ score: Double
    ) throws -> WakeCalibrationTrial {
        try WakeCalibrationTrial(ephemeralCaptureID: id, kind: kind, score: score)
    }

    private func isDeletion(_ effect: WakeCalibrationEffect) -> Bool {
        if case .deleteRawAudio = effect { return true }
        return false
    }
}
