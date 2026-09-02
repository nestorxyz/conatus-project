// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusVoice

public extension WakeCalibrationContract {
    init(verifiedManifest manifest: WakeModelManifest) {
        self.init(
            modelSHA256: manifest.modelSHA256,
            policyRevision: manifest.calibrationPolicy.policyRevision,
            expiresAt: manifest.calibrationPolicy.expiresAt,
            supportedArchitecture: manifest.supportScope.hardwareArchitectures.first ?? "",
            minimumMacOSMajorVersion: manifest.supportScope.minimumMacOSMajorVersion,
            supportedMicrophoneClass: manifest.supportScope.microphoneClasses.first ?? "",
            positiveTrialCount: manifest.calibrationPolicy.positiveTrialCount,
            hardNegativeTrialCount: manifest.calibrationPolicy.hardNegativeTrialCount,
            maximumFalseRejects: manifest.calibrationPolicy.maximumFalseRejects,
            maximumFalseAccepts: manifest.calibrationPolicy.maximumFalseAccepts,
            thresholdCandidates: manifest.calibrationPolicy.thresholdCandidates
        )
    }
}
