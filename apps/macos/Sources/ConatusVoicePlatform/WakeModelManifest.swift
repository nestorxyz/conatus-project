// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CryptoKit
import Foundation

public struct WakeTrainingDataSource: Codable, Equatable, Sendable {
    public let sourceID: String
    public let licenseIdentifier: String
    public let contentSHA256: String
    public let sampleCount: Int

    public init(sourceID: String, licenseIdentifier: String, contentSHA256: String, sampleCount: Int) {
        self.sourceID = sourceID
        self.licenseIdentifier = licenseIdentifier
        self.contentSHA256 = contentSHA256
        self.sampleCount = sampleCount
    }
}

public struct WakeModelEvaluation: Codable, Equatable, Sendable {
    public let corpusSHA256: String
    public let positiveCount: Int
    public let negativeMinutes: Int
    public let falseAccepts: Int
    public let falseRejects: Int
    public let accentTags: [String]
    public let hardwareModels: [String]

    public init(
        corpusSHA256: String,
        positiveCount: Int,
        negativeMinutes: Int,
        falseAccepts: Int,
        falseRejects: Int,
        accentTags: [String],
        hardwareModels: [String]
    ) {
        self.corpusSHA256 = corpusSHA256
        self.positiveCount = positiveCount
        self.negativeMinutes = negativeMinutes
        self.falseAccepts = falseAccepts
        self.falseRejects = falseRejects
        self.accentTags = accentTags
        self.hardwareModels = hardwareModels
    }
}

public struct WakeModelManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let modelFileName: String
    public let modelSHA256: String
    public let modelLicenseIdentifier: String
    public let distributionApprovalReference: String
    public let wakeLabel: String
    public let backgroundLabel: String
    public let sampleRate: Int
    public let trainingRecipeSHA256: String
    public let trainingDataSources: [WakeTrainingDataSource]
    public let evaluation: WakeModelEvaluation

    public init(
        schemaVersion: Int,
        modelFileName: String,
        modelSHA256: String,
        modelLicenseIdentifier: String,
        distributionApprovalReference: String,
        wakeLabel: String,
        backgroundLabel: String,
        sampleRate: Int,
        trainingRecipeSHA256: String,
        trainingDataSources: [WakeTrainingDataSource],
        evaluation: WakeModelEvaluation
    ) {
        self.schemaVersion = schemaVersion
        self.modelFileName = modelFileName
        self.modelSHA256 = modelSHA256
        self.modelLicenseIdentifier = modelLicenseIdentifier
        self.distributionApprovalReference = distributionApprovalReference
        self.wakeLabel = wakeLabel
        self.backgroundLabel = backgroundLabel
        self.sampleRate = sampleRate
        self.trainingRecipeSHA256 = trainingRecipeSHA256
        self.trainingDataSources = trainingDataSources
        self.evaluation = evaluation
    }
}

public enum WakeDistributionPolicy {
    private static let approvedLicenseIdentifiers: Set<String> = [
        "AGPL-3.0-or-later",
        "Apache-2.0",
        "BSD-2-Clause",
        "BSD-3-Clause",
        "CC-BY-4.0",
        "CC0-1.0",
        "Conatus-Owned-1.0",
        "MIT",
    ]

    public static func allowsCommercialUse(_ licenseIdentifier: String) -> Bool {
        let lowered = licenseIdentifier.lowercased()
        let tokens = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let isNoncommercial = lowered.contains("noncommercial")
            || tokens.contains("nc")
            || tokens.indices.dropLast().contains(where: {
                tokens[$0] == "non" && tokens[$0 + 1] == "commercial"
            })
        return approvedLicenseIdentifiers.contains(licenseIdentifier) && !isNoncommercial
    }
}

public enum WakeModelManifestError: Error, Equatable, Sendable {
    case malformed
    case unknownField
    case unsupportedVersion
    case invalidEvidence
    case noncommercialLicense
    case unexpectedModelFile
    case digestMismatch
}

public enum WakeModelVerifier {
    private static let rootKeys = Set([
        "schemaVersion", "modelFileName", "modelSHA256", "modelLicenseIdentifier",
        "distributionApprovalReference", "wakeLabel", "backgroundLabel", "sampleRate",
        "trainingRecipeSHA256", "trainingDataSources", "evaluation",
    ])
    private static let sourceKeys = Set(["sourceID", "licenseIdentifier", "contentSHA256", "sampleCount"])
    private static let evaluationKeys = Set([
        "corpusSHA256", "positiveCount", "negativeMinutes", "falseAccepts", "falseRejects",
        "accentTags", "hardwareModels",
    ])

    public static func verify(
        manifestData: Data,
        modelData: Data,
        expectedModelFileName: String
    ) throws -> WakeModelManifest {
        let manifest = try decodeStrict(manifestData)
        guard manifest.schemaVersion == 1 else { throw WakeModelManifestError.unsupportedVersion }
        try validateEvidence(manifest)
        guard manifest.modelFileName == expectedModelFileName else {
            throw WakeModelManifestError.unexpectedModelFile
        }
        let digest = SHA256.hash(data: modelData).map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.modelSHA256 else { throw WakeModelManifestError.digestMismatch }
        return manifest
    }

    private static func decodeStrict(_ data: Data) throws -> WakeModelManifest {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw WakeModelManifestError.malformed
        }
        guard let object = raw as? [String: Any] else { throw WakeModelManifestError.malformed }
        guard Set(object.keys) == rootKeys else { throw WakeModelManifestError.unknownField }
        guard let sources = object["trainingDataSources"] as? [[String: Any]] else {
            throw WakeModelManifestError.malformed
        }
        guard sources.allSatisfy({ Set($0.keys) == sourceKeys }) else {
            throw WakeModelManifestError.unknownField
        }
        guard
            let evaluation = object["evaluation"] as? [String: Any],
            Set(evaluation.keys) == evaluationKeys
        else {
            throw WakeModelManifestError.unknownField
        }
        do {
            return try JSONDecoder().decode(WakeModelManifest.self, from: data)
        } catch {
            throw WakeModelManifestError.malformed
        }
    }

    private static func validateEvidence(_ manifest: WakeModelManifest) throws {
        guard
            isSafeFileName(manifest.modelFileName),
            manifest.modelFileName.hasSuffix(".mlmodel"),
            isSHA256(manifest.modelSHA256),
            isSHA256(manifest.trainingRecipeSHA256),
            !manifest.modelLicenseIdentifier.isEmpty,
            !manifest.distributionApprovalReference.isEmpty,
            !manifest.wakeLabel.isEmpty,
            !manifest.backgroundLabel.isEmpty,
            manifest.wakeLabel != manifest.backgroundLabel,
            manifest.sampleRate >= 16_000,
            !manifest.trainingDataSources.isEmpty,
            Set(manifest.trainingDataSources.map(\.sourceID)).count == manifest.trainingDataSources.count,
            manifest.trainingDataSources.allSatisfy({
                !$0.sourceID.isEmpty && !$0.licenseIdentifier.isEmpty
                    && isSHA256($0.contentSHA256) && $0.sampleCount > 0
            }),
            isSHA256(manifest.evaluation.corpusSHA256),
            manifest.evaluation.positiveCount > 0,
            manifest.evaluation.negativeMinutes > 0,
            manifest.evaluation.falseAccepts >= 0,
            manifest.evaluation.falseRejects >= 0,
            manifest.evaluation.falseRejects <= manifest.evaluation.positiveCount,
            !manifest.evaluation.accentTags.isEmpty,
            !manifest.evaluation.hardwareModels.isEmpty
        else {
            throw WakeModelManifestError.invalidEvidence
        }
        let licenses = [manifest.modelLicenseIdentifier]
            + manifest.trainingDataSources.map(\.licenseIdentifier)
        guard licenses.allSatisfy(WakeDistributionPolicy.allowsCommercialUse) else {
            throw WakeModelManifestError.noncommercialLicense
        }
    }

    private static func isSafeFileName(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && !value.contains("\\") && value != "." && value != ".."
    }

    private static func isSHA256(_ value: String) -> Bool {
        let hexadecimal = Set("0123456789abcdef")
        return value.count == 64 && value.allSatisfy(hexadecimal.contains)
    }

}
