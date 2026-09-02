// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import ConatusVoicePlatform
import CryptoKit
import Foundation

public enum WakeDatasetLabel: String, Codable, CaseIterable, Sendable {
    case wake = "hey_conatus"
    case background
}

public enum WakeDatasetSplit: String, Codable, CaseIterable, Sendable {
    case training
    case validation
    case testing
}

public struct WakeDatasetSource: Codable, Equatable, Sendable {
    public let sourceID: String
    public let subjectID: String
    public let licenseIdentifier: String
    public let consentReference: String
    public let accentTags: [String]
}

public struct WakeDatasetClip: Codable, Equatable, Sendable {
    public let clipID: String
    public let relativePath: String
    public let sha256: String
    public let sourceID: String
    public let recordingSessionID: String
    public let label: WakeDatasetLabel
    public let split: WakeDatasetSplit
    public let sampleRate: Int
    public let channelCount: Int
    public let durationMilliseconds: Int
}

public struct WakeDatasetManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let datasetID: String
    public let distributionApprovalReference: String
    public let sources: [WakeDatasetSource]
    public let clips: [WakeDatasetClip]
}

public struct InspectedWakeAudio: Equatable, Sendable {
    public let sampleRate: Int
    public let channelCount: Int
    public let durationMilliseconds: Int

    public init(sampleRate: Int, channelCount: Int, durationMilliseconds: Int) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.durationMilliseconds = durationMilliseconds
    }
}

public protocol WakeAudioInspecting {
    func inspect(_ url: URL) throws -> InspectedWakeAudio
}

public struct AVFoundationWakeAudioInspector: WakeAudioInspecting {
    public init() {}

    public func inspect(_ url: URL) throws -> InspectedWakeAudio {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = Int(format.sampleRate.rounded())
        guard
            sampleRate > 0,
            abs(format.sampleRate - Double(sampleRate)) < 0.001,
            format.channelCount > 0,
            file.length > 0
        else {
            throw WakeDatasetError.invalidAudio
        }
        let milliseconds = Int((Double(file.length) / format.sampleRate * 1_000).rounded())
        return InspectedWakeAudio(
            sampleRate: sampleRate,
            channelCount: Int(format.channelCount),
            durationMilliseconds: milliseconds
        )
    }
}

public struct ValidatedWakeDataset: Sendable {
    public let manifest: WakeDatasetManifest
    public let rootURL: URL
    public let corpusSHA256: String
    public let files: [WakeDatasetSplit: [WakeDatasetLabel: [URL]]]

    public func urls(split: WakeDatasetSplit, label: WakeDatasetLabel) -> [URL] {
        files[split]?[label] ?? []
    }
}

public enum WakeDatasetError: Error, Equatable, Sendable {
    case malformedManifest
    case unknownField
    case unsupportedVersion
    case invalidEvidence
    case noncommercialLicense
    case unsafePath
    case missingFile
    case symlinkedFile
    case digestMismatch
    case invalidAudio
    case audioMetadataMismatch
    case insufficientSplit
    case splitLeakage
}

public enum WakeDatasetValidator {
    private static let rootKeys = Set([
        "schemaVersion", "datasetID", "distributionApprovalReference", "sources", "clips",
    ])
    private static let sourceKeys = Set([
        "sourceID", "subjectID", "licenseIdentifier", "consentReference", "accentTags",
    ])
    private static let clipKeys = Set([
        "clipID", "relativePath", "sha256", "sourceID", "recordingSessionID", "label", "split",
        "sampleRate", "channelCount", "durationMilliseconds",
    ])

    public static func validate(
        manifestData: Data,
        datasetRoot: URL,
        inspector: any WakeAudioInspecting = AVFoundationWakeAudioInspector()
    ) throws -> ValidatedWakeDataset {
        let manifest = try decodeStrict(manifestData)
        guard manifest.schemaVersion == 1 else { throw WakeDatasetError.unsupportedVersion }
        try validateEvidence(manifest)

        let fileManager = FileManager.default
        let root = datasetRoot.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WakeDatasetError.missingFile
        }

        var files = emptyFileMap()
        var sampleRates = Set<Int>()
        for clip in manifest.clips {
            let fileURL = try resolveFile(clip.relativePath, under: root, fileManager: fileManager)
            guard try sha256(fileURL) == clip.sha256 else { throw WakeDatasetError.digestMismatch }
            let audio = try inspector.inspect(fileURL)
            guard audio.sampleRate >= 16_000, audio.channelCount == 1 else {
                throw WakeDatasetError.invalidAudio
            }
            guard
                audio.sampleRate == clip.sampleRate,
                audio.channelCount == clip.channelCount,
                abs(audio.durationMilliseconds - clip.durationMilliseconds) <= 20
            else {
                throw WakeDatasetError.audioMetadataMismatch
            }
            sampleRates.insert(audio.sampleRate)
            files[clip.split, default: [:]][clip.label, default: []].append(fileURL)
        }
        guard sampleRates.count == 1 else { throw WakeDatasetError.audioMetadataMismatch }
        try validateSplitCounts(manifest, files: files)

        return ValidatedWakeDataset(
            manifest: manifest,
            rootURL: root,
            corpusSHA256: corpusDigest(manifest.clips.filter { $0.split == .testing }),
            files: files.mapValues { labels in
                labels.mapValues { $0.sorted { $0.path < $1.path } }
            }
        )
    }

    private static func decodeStrict(_ data: Data) throws -> WakeDatasetManifest {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw WakeDatasetError.malformedManifest
        }
        guard let object = raw as? [String: Any] else { throw WakeDatasetError.malformedManifest }
        guard Set(object.keys) == rootKeys else { throw WakeDatasetError.unknownField }
        guard
            let sources = object["sources"] as? [[String: Any]],
            sources.allSatisfy({ Set($0.keys) == sourceKeys }),
            let clips = object["clips"] as? [[String: Any]],
            clips.allSatisfy({ Set($0.keys) == clipKeys })
        else {
            throw WakeDatasetError.unknownField
        }
        do {
            return try JSONDecoder().decode(WakeDatasetManifest.self, from: data)
        } catch {
            throw WakeDatasetError.malformedManifest
        }
    }

    private static func validateEvidence(_ manifest: WakeDatasetManifest) throws {
        let groupedSources = Dictionary(grouping: manifest.sources, by: \.sourceID)
        guard
            !manifest.datasetID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !manifest.distributionApprovalReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !manifest.sources.isEmpty,
            groupedSources.values.allSatisfy({ $0.count == 1 }),
            manifest.sources.allSatisfy({
                !$0.sourceID.isEmpty && !$0.subjectID.isEmpty && !$0.consentReference.isEmpty
                    && !$0.accentTags.isEmpty
            }),
            !manifest.clips.isEmpty,
            Set(manifest.clips.map(\.clipID)).count == manifest.clips.count,
            Set(manifest.clips.map(\.relativePath)).count == manifest.clips.count,
            manifest.clips.allSatisfy({
                !$0.clipID.isEmpty && !$0.recordingSessionID.isEmpty && !$0.sourceID.isEmpty
                    && isSHA256($0.sha256) && $0.sampleRate >= 16_000 && $0.channelCount == 1
                    && $0.durationMilliseconds > 0
            })
        else {
            throw WakeDatasetError.invalidEvidence
        }
        let sourcesByID = groupedSources.mapValues { $0[0] }
        guard manifest.clips.allSatisfy({ sourcesByID[$0.sourceID] != nil }) else {
            throw WakeDatasetError.invalidEvidence
        }
        guard manifest.sources.allSatisfy({
            WakeDistributionPolicy.allowsCommercialUse($0.licenseIdentifier)
        }) else {
            throw WakeDatasetError.noncommercialLicense
        }

        let sessions = Dictionary(grouping: manifest.clips, by: \.recordingSessionID)
        guard sessions.values.allSatisfy({ Set($0.map(\.split)).count == 1 }) else {
            throw WakeDatasetError.splitLeakage
        }
        let subjectBySource = sourcesByID.mapValues(\.subjectID)
        let trainingWakeSubjects = Set(manifest.clips.compactMap {
            $0.split == .training && $0.label == .wake ? subjectBySource[$0.sourceID] : nil
        })
        let testingWakeSubjects = Set(manifest.clips.compactMap {
            $0.split == .testing && $0.label == .wake ? subjectBySource[$0.sourceID] : nil
        })
        guard trainingWakeSubjects.isDisjoint(with: testingWakeSubjects) else {
            throw WakeDatasetError.splitLeakage
        }
    }

    private static func validateSplitCounts(
        _ manifest: WakeDatasetManifest,
        files: [WakeDatasetSplit: [WakeDatasetLabel: [URL]]]
    ) throws {
        for label in WakeDatasetLabel.allCases {
            guard
                (files[.training]?[label]?.count ?? 0) >= 10,
                (files[.validation]?[label]?.count ?? 0) >= 1,
                (files[.testing]?[label]?.count ?? 0) >= 1
            else {
                throw WakeDatasetError.insufficientSplit
            }
        }
        let testingBackgroundMilliseconds = manifest.clips
            .filter { $0.split == .testing && $0.label == .background }
            .reduce(0) { $0 + $1.durationMilliseconds }
        guard testingBackgroundMilliseconds >= 60_000 else {
            throw WakeDatasetError.insufficientSplit
        }
    }

    private static func resolveFile(
        _ relativePath: String,
        under root: URL,
        fileManager: FileManager
    ) throws -> URL {
        let path = relativePath as NSString
        let components = path.pathComponents
        guard
            !relativePath.isEmpty,
            !path.isAbsolutePath,
            !components.contains(".."),
            !components.contains("."),
            !components.contains("/"),
            !relativePath.contains("\\")
        else {
            throw WakeDatasetError.unsafePath
        }
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath()
        guard candidate.path == resolved.path else { throw WakeDatasetError.symlinkedFile }
        guard resolved.path.hasPrefix(root.path + "/") else { throw WakeDatasetError.unsafePath }
        let values = try resolved.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true else { throw WakeDatasetError.missingFile }
        guard values.isSymbolicLink != true else { throw WakeDatasetError.symlinkedFile }
        return resolved
    }

    public static func sha256(_ fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func corpusDigest(_ clips: [WakeDatasetClip]) -> String {
        let material = clips.sorted { $0.clipID < $1.clipID }.map {
            "\($0.clipID)\t\($0.sha256)\t\($0.label.rawValue)\t\($0.split.rawValue)"
        }.joined(separator: "\n")
        return SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func emptyFileMap() -> [WakeDatasetSplit: [WakeDatasetLabel: [URL]]] {
        Dictionary(uniqueKeysWithValues: WakeDatasetSplit.allCases.map { ($0, [:]) })
    }

    private static func isSHA256(_ value: String) -> Bool {
        let hexadecimal = Set("0123456789abcdef")
        return value.count == 64 && value.allSatisfy(hexadecimal.contains)
    }
}
