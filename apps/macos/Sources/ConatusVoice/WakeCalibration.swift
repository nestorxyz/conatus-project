// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct WakeCalibrationContract: Equatable, Sendable {
    public let modelSHA256: String
    public let policyRevision: String
    public let expiresAt: Date
    public let supportedArchitecture: String
    public let minimumMacOSMajorVersion: Int
    public let supportedMicrophoneClass: String
    public let positiveTrialCount: Int
    public let hardNegativeTrialCount: Int
    public let maximumFalseRejects: Int
    public let maximumFalseAccepts: Int
    public let thresholdCandidates: [Double]

    public init(
        modelSHA256: String,
        policyRevision: String,
        expiresAt: Date,
        supportedArchitecture: String,
        minimumMacOSMajorVersion: Int,
        supportedMicrophoneClass: String,
        positiveTrialCount: Int,
        hardNegativeTrialCount: Int,
        maximumFalseRejects: Int,
        maximumFalseAccepts: Int,
        thresholdCandidates: [Double]
    ) {
        self.modelSHA256 = modelSHA256
        self.policyRevision = policyRevision
        self.expiresAt = expiresAt
        self.supportedArchitecture = supportedArchitecture
        self.minimumMacOSMajorVersion = minimumMacOSMajorVersion
        self.supportedMicrophoneClass = supportedMicrophoneClass
        self.positiveTrialCount = positiveTrialCount
        self.hardNegativeTrialCount = hardNegativeTrialCount
        self.maximumFalseRejects = maximumFalseRejects
        self.maximumFalseAccepts = maximumFalseAccepts
        self.thresholdCandidates = thresholdCandidates
    }
}

public struct WakeCalibrationDevice: Equatable, Sendable {
    public let opaqueDeviceID: String
    public let architecture: String
    public let macOSMajorVersion: Int
    public let microphoneClass: String

    public init(
        opaqueDeviceID: String,
        architecture: String,
        macOSMajorVersion: Int,
        microphoneClass: String
    ) {
        self.opaqueDeviceID = opaqueDeviceID
        self.architecture = architecture
        self.macOSMajorVersion = macOSMajorVersion
        self.microphoneClass = microphoneClass
    }
}

public enum WakeCalibrationTrialKind: Equatable, Sendable {
    case positive
    case hardNegative
}

public struct WakeCalibrationTrial: Equatable, Sendable {
    public let ephemeralCaptureID: String
    public let kind: WakeCalibrationTrialKind
    public let score: Double

    public init(ephemeralCaptureID: String, kind: WakeCalibrationTrialKind, score: Double) throws {
        guard !ephemeralCaptureID.isEmpty else {
            throw WakeCalibrationError.invalidTrial
        }
        self.ephemeralCaptureID = ephemeralCaptureID
        self.kind = kind
        self.score = score
    }
}

public enum WakeCalibrationFailure: Equatable, Sendable {
    case invalidContract
    case stalePolicy
    case unsupportedDevice
    case deviceMismatch
    case receiptMismatch
    case scoreGateFailed
}

public enum WakeCalibrationState: Equatable, Sendable {
    case idle
    case collectingPositive(completed: Int, required: Int)
    case collectingHardNegative(completed: Int, required: Int)
    case passed(threshold: Double, deviceID: String, modelSHA256: String, policyRevision: String)
    case failed(WakeCalibrationFailure)
    case manualFallback(WakeCalibrationFailure)
}

public enum WakeCalibrationEffect: Equatable, Sendable {
    case deleteRawAudio(ephemeralCaptureID: String)
    case enableWake(threshold: Double)
    case disableWake
    case showManualFallback
}

public struct WakeCalibrationReceipt: Equatable, Sendable {
    public let threshold: Double
    public let opaqueDeviceID: String
    public let modelSHA256: String
    public let policyRevision: String

    public init(threshold: Double, opaqueDeviceID: String, modelSHA256: String, policyRevision: String) {
        self.threshold = threshold
        self.opaqueDeviceID = opaqueDeviceID
        self.modelSHA256 = modelSHA256
        self.policyRevision = policyRevision
    }
}

public enum WakeCalibrationError: Error, Equatable, Sendable {
    case invalidTrial
    case invalidState
}

public struct LocalWakeCalibration: Sendable {
    public private(set) var state: WakeCalibrationState = .idle

    private let contract: WakeCalibrationContract
    private let device: WakeCalibrationDevice
    private var positiveScores: [Double] = []
    private var hardNegativeScores: [Double] = []

    public init(contract: WakeCalibrationContract, device: WakeCalibrationDevice) {
        self.contract = contract
        self.device = device
    }

    public mutating func start(now: Date) throws -> [WakeCalibrationEffect] {
        guard state == .idle else { throw WakeCalibrationError.invalidState }
        guard Self.isValid(contract) else {
            state = .manualFallback(.invalidContract)
            return [.disableWake, .showManualFallback]
        }
        return beginValidatedRun(now: now)
    }

    public mutating func restore(_ receipt: WakeCalibrationReceipt, now: Date) throws -> [WakeCalibrationEffect] {
        guard state == .idle else { throw WakeCalibrationError.invalidState }
        guard Self.isValid(contract) else {
            state = .manualFallback(.invalidContract)
            return [.disableWake, .showManualFallback]
        }
        guard now < contract.expiresAt else {
            state = .manualFallback(.stalePolicy)
            return [.disableWake, .showManualFallback]
        }
        guard supportsCurrentDevice else {
            state = .manualFallback(.unsupportedDevice)
            return [.disableWake, .showManualFallback]
        }
        guard receipt.opaqueDeviceID == device.opaqueDeviceID else {
            state = .manualFallback(.deviceMismatch)
            return [.disableWake, .showManualFallback]
        }
        guard
            receipt.modelSHA256 == contract.modelSHA256,
            receipt.policyRevision == contract.policyRevision,
            contract.thresholdCandidates.contains(receipt.threshold)
        else {
            state = .manualFallback(.receiptMismatch)
            return [.disableWake, .showManualFallback]
        }
        state = .passed(
            threshold: receipt.threshold,
            deviceID: receipt.opaqueDeviceID,
            modelSHA256: receipt.modelSHA256,
            policyRevision: receipt.policyRevision
        )
        return [.enableWake(threshold: receipt.threshold)]
    }

    public mutating func retry(now: Date, device: WakeCalibrationDevice) throws -> [WakeCalibrationEffect] {
        switch state {
        case .failed, .manualFallback:
            break
        default:
            throw WakeCalibrationError.invalidState
        }
        guard device == self.device else {
            state = .manualFallback(.deviceMismatch)
            return [.disableWake, .showManualFallback]
        }
        positiveScores.removeAll(keepingCapacity: true)
        hardNegativeScores.removeAll(keepingCapacity: true)
        return beginValidatedRun(now: now)
    }

    public mutating func submit(_ trial: WakeCalibrationTrial) throws -> [WakeCalibrationEffect] {
        let deletion = WakeCalibrationEffect.deleteRawAudio(ephemeralCaptureID: trial.ephemeralCaptureID)
        guard trial.score.isFinite, (0 ... 1).contains(trial.score) else {
            state = .failed(.invalidContract)
            return [deletion, .disableWake, .showManualFallback]
        }
        switch (state, trial.kind) {
        case (.collectingPositive, .positive):
            positiveScores.append(trial.score)
            if positiveScores.count == contract.positiveTrialCount {
                state = .collectingHardNegative(completed: 0, required: contract.hardNegativeTrialCount)
            } else {
                state = .collectingPositive(
                    completed: positiveScores.count,
                    required: contract.positiveTrialCount
                )
            }
            return [deletion]
        case (.collectingHardNegative, .hardNegative):
            hardNegativeScores.append(trial.score)
            guard hardNegativeScores.count == contract.hardNegativeTrialCount else {
                state = .collectingHardNegative(
                    completed: hardNegativeScores.count,
                    required: contract.hardNegativeTrialCount
                )
                return [deletion]
            }
            if let threshold = passingThreshold() {
                state = .passed(
                    threshold: threshold,
                    deviceID: device.opaqueDeviceID,
                    modelSHA256: contract.modelSHA256,
                    policyRevision: contract.policyRevision
                )
                return [deletion, .enableWake(threshold: threshold)]
            }
            state = .failed(.scoreGateFailed)
            return [deletion, .disableWake, .showManualFallback]
        case (.collectingPositive, _), (.collectingHardNegative, _):
            state = .failed(.invalidContract)
            return [deletion, .disableWake, .showManualFallback]
        default:
            state = .failed(.invalidContract)
            return [deletion, .disableWake, .showManualFallback]
        }
    }

    private mutating func beginValidatedRun(now: Date) -> [WakeCalibrationEffect] {
        guard now < contract.expiresAt else {
            state = .manualFallback(.stalePolicy)
            return [.disableWake, .showManualFallback]
        }
        guard supportsCurrentDevice else {
            state = .manualFallback(.unsupportedDevice)
            return [.disableWake, .showManualFallback]
        }
        state = .collectingPositive(completed: 0, required: contract.positiveTrialCount)
        return [.disableWake]
    }

    private func passingThreshold() -> Double? {
        contract.thresholdCandidates.first { threshold in
            positiveScores.filter { $0 < threshold }.count <= contract.maximumFalseRejects
                && hardNegativeScores.filter { $0 >= threshold }.count <= contract.maximumFalseAccepts
        }
    }

    private var supportsCurrentDevice: Bool {
        device.architecture == contract.supportedArchitecture
            && device.macOSMajorVersion >= contract.minimumMacOSMajorVersion
            && device.microphoneClass == contract.supportedMicrophoneClass
            && !device.opaqueDeviceID.isEmpty
    }

    private static func isValid(_ contract: WakeCalibrationContract) -> Bool {
        contract.modelSHA256.count == 64
            && contract.modelSHA256.allSatisfy { $0.isHexDigit && !$0.isUppercase }
            && !contract.policyRevision.isEmpty
            && contract.supportedArchitecture == "arm64"
            && contract.minimumMacOSMajorVersion >= 14
            && contract.supportedMicrophoneClass == "built_in"
            && contract.positiveTrialCount > 0
            && contract.hardNegativeTrialCount > 0
            && (0 ..< contract.positiveTrialCount).contains(contract.maximumFalseRejects)
            && (0 ..< contract.hardNegativeTrialCount).contains(contract.maximumFalseAccepts)
            && !contract.thresholdCandidates.isEmpty
            && contract.thresholdCandidates.allSatisfy { $0.isFinite && (0 ... 1).contains($0) }
            && contract.thresholdCandidates == contract.thresholdCandidates.sorted()
            && Set(contract.thresholdCandidates).count == contract.thresholdCandidates.count
    }
}
