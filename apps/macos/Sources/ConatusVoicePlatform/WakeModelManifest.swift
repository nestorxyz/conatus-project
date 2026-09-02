// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CryptoKit
import Foundation

public struct WakeTrainingDataSource: Codable, Equatable, Sendable {
    public let sourceID: String
    public let licenseIdentifier: String
    public let contentSHA256: String
    public let sampleCount: Int
}

public struct WakeModelEvaluation: Codable, Equatable, Sendable {
    public let corpusSHA256: String
    public let positiveCount: Int
    public let negativeMinutes: Int
    public let falseAccepts: Int
    public let falseRejects: Int
    public let accentTags: [String]
    public let hardwareModels: [String]
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
        guard !licenses.contains(where: isNoncommercial) else {
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

    private static func isNoncommercial(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let tokens = lowered.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return lowered.contains("noncommercial")
            || tokens.contains("nc")
            || tokens.indices.dropLast().contains(where: {
                tokens[$0] == "non" && tokens[$0 + 1] == "commercial"
            })
    }
}
