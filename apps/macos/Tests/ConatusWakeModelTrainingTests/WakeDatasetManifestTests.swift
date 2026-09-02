// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CryptoKit
import Foundation
import Testing
@testable import ConatusWakeModelTraining

@Suite("Wake dataset provenance")
struct WakeDatasetManifestTests {
    @Test("validates commercial, consented, split-isolated audio evidence")
    func validatesDataset() throws {
        let fixture = try DatasetFixture()
        defer { fixture.remove() }

        let dataset = try WakeDatasetValidator.validate(
            manifestData: fixture.manifestData(),
            datasetRoot: fixture.root,
            inspector: FixtureAudioInspector()
        )

        #expect(dataset.manifest.clips.count == 24)
        #expect(dataset.urls(split: .training, label: .wake).count == 10)
        #expect(dataset.urls(split: .testing, label: .background).count == 1)
        #expect(dataset.corpusSHA256.count == 64)
    }

    @Test("rejects unknown manifest fields")
    func rejectsUnknownField() throws {
        let fixture = try DatasetFixture()
        defer { fixture.remove() }
        var manifest = fixture.manifest
        manifest["unexpected"] = true

        #expect(throws: WakeDatasetError.unknownField) {
            try WakeDatasetValidator.validate(
                manifestData: try fixture.encode(manifest),
                datasetRoot: fixture.root,
                inspector: FixtureAudioInspector()
            )
        }
    }

    @Test("rejects noncommercial source material")
    func rejectsNoncommercialSource() throws {
        let fixture = try DatasetFixture()
        defer { fixture.remove() }
        var manifest = fixture.manifest
        var sources = try #require(manifest["sources"] as? [[String: Any]])
        sources[0]["licenseIdentifier"] = "CC-BY-NC-SA-4.0"
        manifest["sources"] = sources

        #expect(throws: WakeDatasetError.noncommercialLicense) {
            try WakeDatasetValidator.validate(
                manifestData: try fixture.encode(manifest),
                datasetRoot: fixture.root,
                inspector: FixtureAudioInspector()
            )
        }
    }

    @Test("rejects an unreviewed license identifier")
    func rejectsUnknownLicense() throws {
        let fixture = try DatasetFixture()
        defer { fixture.remove() }
        var manifest = fixture.manifest
        var sources = try #require(manifest["sources"] as? [[String: Any]])
        sources[0]["licenseIdentifier"] = "Custom-Maybe-Commercial"
        manifest["sources"] = sources

        #expect(throws: WakeDatasetError.noncommercialLicense) {
            try WakeDatasetValidator.validate(
                manifestData: try fixture.encode(manifest),
                datasetRoot: fixture.root,
                inspector: FixtureAudioInspector()
            )
        }
    }

    @Test("rejects path traversal before file access")
    func rejectsPathTraversal() throws {
        let fixture = try DatasetFixture()
        defer { fixture.remove() }
        var manifest = fixture.manifest
        var clips = try #require(manifest["clips"] as? [[String: Any]])
        clips[0]["relativePath"] = "../private.wav"
        manifest["clips"] = clips

        #expect(throws: WakeDatasetError.unsafePath) {
            try WakeDatasetValidator.validate(
                manifestData: try fixture.encode(manifest),
                datasetRoot: fixture.root,
                inspector: FixtureAudioInspector()
            )
        }
    }

    @Test("rejects changed audio bytes")
    func rejectsDigestMismatch() throws {
        let fixture = try DatasetFixture()
        defer { fixture.remove() }
        let first = try #require((fixture.manifest["clips"] as? [[String: Any]])?.first)
        let path = try #require(first["relativePath"] as? String)
        try Data("changed".utf8).write(to: fixture.root.appendingPathComponent(path))

        #expect(throws: WakeDatasetError.digestMismatch) {
            try WakeDatasetValidator.validate(
                manifestData: fixture.manifestData(),
                datasetRoot: fixture.root,
                inspector: FixtureAudioInspector()
            )
        }
    }

    @Test("rejects recording sessions split across evaluation boundaries")
    func rejectsSplitLeakage() throws {
        let fixture = try DatasetFixture()
        defer { fixture.remove() }
        var manifest = fixture.manifest
        var clips = try #require(manifest["clips"] as? [[String: Any]])
        clips[10]["recordingSessionID"] = clips[0]["recordingSessionID"]
        manifest["clips"] = clips

        #expect(throws: WakeDatasetError.splitLeakage) {
            try WakeDatasetValidator.validate(
                manifestData: try fixture.encode(manifest),
                datasetRoot: fixture.root,
                inspector: FixtureAudioInspector()
            )
        }
    }

    @Test("requires a held-out wake subject for testing")
    func rejectsWakeSubjectLeakage() throws {
        let fixture = try DatasetFixture()
        defer { fixture.remove() }
        var manifest = fixture.manifest
        var clips = try #require(manifest["clips"] as? [[String: Any]])
        let testingWakeIndex = try #require(clips.firstIndex {
            ($0["split"] as? String) == WakeDatasetSplit.testing.rawValue
                && ($0["label"] as? String) == WakeDatasetLabel.wake.rawValue
        })
        clips[testingWakeIndex]["sourceID"] = "source-1"
        manifest["clips"] = clips

        #expect(throws: WakeDatasetError.splitLeakage) {
            try WakeDatasetValidator.validate(
                manifestData: try fixture.encode(manifest),
                datasetRoot: fixture.root,
                inspector: FixtureAudioInspector()
            )
        }
    }

    @Test("training recipe is immutable, commercial, and digestible")
    func validatesRecipe() throws {
        let recipe = WakeTrainingRecipe(modelLicenseIdentifier: "AGPL-3.0-or-later")
        #expect(try recipe.sha256().count == 64)
        #expect(throws: WakeModelTrainingError.invalidRecipe) {
            try WakeTrainingRecipe(modelLicenseIdentifier: "CC-BY-NC-SA-4.0").validate()
        }
    }
}

private struct FixtureAudioInspector: WakeAudioInspecting {
    func inspect(_ url: URL) throws -> InspectedWakeAudio {
        let duration = url.lastPathComponent.contains("testing-background") ? 60_000 : 1_000
        return InspectedWakeAudio(sampleRate: 16_000, channelCount: 1, durationMilliseconds: duration)
    }
}

private final class DatasetFixture {
    let root: URL
    var manifest: [String: Any]

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("conatus-wake-dataset-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        var clips: [[String: Any]] = []
        for label in WakeDatasetLabel.allCases {
            for split in WakeDatasetSplit.allCases {
                let count = split == .training ? 10 : 1
                for index in 0 ..< count {
                    let id = "\(split.rawValue)-\(label.rawValue)-\(index)"
                    let relativePath = "\(id).wav"
                    let data = Data("audio-\(id)".utf8)
                    try data.write(to: root.appendingPathComponent(relativePath))
                    clips.append([
                        "clipID": id,
                        "relativePath": relativePath,
                        "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                        "sourceID": split == .testing && label == .wake ? "source-2" : "source-1",
                        "recordingSessionID": "session-\(id)",
                        "label": label.rawValue,
                        "split": split.rawValue,
                        "sampleRate": 16_000,
                        "channelCount": 1,
                        "durationMilliseconds": split == .testing && label == .background ? 60_000 : 1_000,
                    ])
                }
            }
        }
        manifest = [
            "schemaVersion": 1,
            "datasetID": "conatus-owned-v1",
            "distributionApprovalReference": "approval-2026-09-02",
            "sources": [[
                "sourceID": "source-1",
                "subjectID": "speaker-opaque-1",
                "licenseIdentifier": "CC0-1.0",
                "consentReference": "consent-opaque-1",
                "accentTags": ["es-PE"],
            ], [
                "sourceID": "source-2",
                "subjectID": "speaker-opaque-2",
                "licenseIdentifier": "CC0-1.0",
                "consentReference": "consent-opaque-2",
                "accentTags": ["en-US"],
            ]],
            "clips": clips,
        ]
    }

    func manifestData() throws -> Data {
        try encode(manifest)
    }

    func encode(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
