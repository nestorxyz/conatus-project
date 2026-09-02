// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CryptoKit
import Foundation
import Testing
@testable import ConatusVoicePlatform

@Suite("Wake model provenance")
struct WakeModelManifestTests {
    @Test("accepts complete commercial evidence with a matching artifact")
    func acceptsVerifiedManifest() throws {
        let model = Data("model bytes".utf8)
        let manifest = try manifestData(modelData: model)

        let verified = try WakeModelVerifier.verify(
            manifestData: manifest,
            modelData: model,
            expectedModelFileName: "HeyConatus.mlmodel"
        )

        #expect(verified.wakeLabel == "hey_conatus")
        #expect(verified.trainingDataSources.count == 1)
    }

    @Test("rejects unknown manifest fields")
    func rejectsUnknownField() throws {
        let model = Data("model bytes".utf8)
        var object = try manifestObject(modelData: model)
        object["unexpected"] = true

        #expect(throws: WakeModelManifestError.unknownField) {
            try WakeModelVerifier.verify(
                manifestData: try encode(object),
                modelData: model,
                expectedModelFileName: "HeyConatus.mlmodel"
            )
        }
    }

    @Test("rejects noncommercial model and data licenses", arguments: [
        ("CC-BY-NC-SA-4.0", "Apache-2.0"),
        ("Apache-2.0", "Creative Commons NonCommercial 4.0"),
        ("Apache-2.0", "Creative Commons Non-Commercial 4.0"),
    ])
    func rejectsNoncommercialLicense(modelLicense: String, sourceLicense: String) throws {
        let model = Data("model bytes".utf8)
        var object = try manifestObject(modelData: model)
        object["modelLicenseIdentifier"] = modelLicense
        var sources = try #require(object["trainingDataSources"] as? [[String: Any]])
        sources[0]["licenseIdentifier"] = sourceLicense
        object["trainingDataSources"] = sources

        #expect(throws: WakeModelManifestError.noncommercialLicense) {
            try WakeModelVerifier.verify(
                manifestData: try encode(object),
                modelData: model,
                expectedModelFileName: "HeyConatus.mlmodel"
            )
        }
    }

    @Test("rejects filename drift")
    func rejectsFilenameDrift() throws {
        let model = Data("model bytes".utf8)
        #expect(throws: WakeModelManifestError.unexpectedModelFile) {
            try WakeModelVerifier.verify(
                manifestData: try manifestData(modelData: model),
                modelData: model,
                expectedModelFileName: "Different.mlmodel"
            )
        }
    }

    @Test("rejects artifact digest mismatch")
    func rejectsDigestMismatch() throws {
        #expect(throws: WakeModelManifestError.digestMismatch) {
            try WakeModelVerifier.verify(
                manifestData: try manifestData(modelData: Data("original".utf8)),
                modelData: Data("changed".utf8),
                expectedModelFileName: "HeyConatus.mlmodel"
            )
        }
    }

    @Test("rejects incomplete evaluation evidence")
    func rejectsIncompleteEvaluation() throws {
        let model = Data("model bytes".utf8)
        var object = try manifestObject(modelData: model)
        var evaluation = try #require(object["evaluation"] as? [String: Any])
        evaluation["hardwareModels"] = [String]()
        object["evaluation"] = evaluation

        #expect(throws: WakeModelManifestError.invalidEvidence) {
            try WakeModelVerifier.verify(
                manifestData: try encode(object),
                modelData: model,
                expectedModelFileName: "HeyConatus.mlmodel"
            )
        }
    }

    private func manifestData(modelData: Data) throws -> Data {
        try encode(manifestObject(modelData: modelData))
    }

    private func manifestObject(modelData: Data) throws -> [String: Any] {
        [
            "schemaVersion": 1,
            "modelFileName": "HeyConatus.mlmodel",
            "modelSHA256": sha256(modelData),
            "modelLicenseIdentifier": "Apache-2.0",
            "distributionApprovalReference": "review-2026-08-31",
            "wakeLabel": "hey_conatus",
            "backgroundLabel": "background",
            "sampleRate": 16_000,
            "trainingRecipeSHA256": String(repeating: "a", count: 64),
            "trainingDataSources": [[
                "sourceID": "consented-speakers-v1",
                "licenseIdentifier": "Apache-2.0",
                "contentSHA256": String(repeating: "b", count: 64),
                "sampleCount": 500,
            ]],
            "evaluation": [
                "corpusSHA256": String(repeating: "c", count: 64),
                "positiveCount": 100,
                "negativeMinutes": 120,
                "falseAccepts": 1,
                "falseRejects": 3,
                "accentTags": ["es-PE", "en-US"],
                "hardwareModels": ["MacBookPro18,3"],
            ],
        ]
    }

    private func encode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
