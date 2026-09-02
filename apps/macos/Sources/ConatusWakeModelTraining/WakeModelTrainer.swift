// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusVoicePlatform
import CoreML
import CreateML
import CryptoKit
import Foundation

public struct WakeTrainingRecipe: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let modelFileName: String
    public let modelLicenseIdentifier: String
    public let maxIterations: Int
    public let overlapFactor: Double
    public let featureExtractionTimeWindowSeconds: Double
    public let featureExtractor: String
    public let classifier: String

    public init(
        modelFileName: String = "HeyConatus.mlmodel",
        modelLicenseIdentifier: String,
        maxIterations: Int = 25,
        overlapFactor: Double = 0.5,
        featureExtractionTimeWindowSeconds: Double = 1.0
    ) {
        schemaVersion = 1
        self.modelFileName = modelFileName
        self.modelLicenseIdentifier = modelLicenseIdentifier
        self.maxIterations = maxIterations
        self.overlapFactor = overlapFactor
        self.featureExtractionTimeWindowSeconds = featureExtractionTimeWindowSeconds
        featureExtractor = "audioFeaturePrint.sound.revision1"
        classifier = "logisticRegressor"
    }

    public func validate() throws {
        guard
            schemaVersion == 1,
            modelFileName == "HeyConatus.mlmodel",
            WakeDistributionPolicy.allowsCommercialUse(modelLicenseIdentifier),
            maxIterations > 0,
            overlapFactor.isFinite,
            (0 ..< 1).contains(overlapFactor),
            featureExtractionTimeWindowSeconds.isFinite,
            featureExtractionTimeWindowSeconds > 0,
            featureExtractor == "audioFeaturePrint.sound.revision1",
            classifier == "logisticRegressor"
        else {
            throw WakeModelTrainingError.invalidRecipe
        }
    }

    public func sha256() throws -> String {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(self))
            .map { String(format: "%02x", $0) }.joined()
    }
}

public struct WakeModelTrainingResult: Equatable, Sendable {
    public let modelURL: URL
    public let manifestURL: URL
    public let falseAccepts: Int
    public let falseRejects: Int
}

public enum WakeModelTrainingError: Error, Equatable, Sendable {
    case invalidRecipe
    case invalidMetrics
    case predictionCountMismatch
    case outputAlreadyExists
    case temporaryCleanupFailed
}

public struct WakeModelTrainer {
    public init() {}

    public func train(
        dataset: ValidatedWakeDataset,
        recipe: WakeTrainingRecipe,
        outputDirectory: URL,
        evaluationHardwareModels: [String]
    ) throws -> WakeModelTrainingResult {
        try recipe.validate()
        guard !evaluationHardwareModels.isEmpty, evaluationHardwareModels.allSatisfy({ !$0.isEmpty }) else {
            throw WakeModelTrainingError.invalidRecipe
        }

        return try withPrivateSnapshot { workingDirectory, fileManager in
            let snapshot = try snapshotFiles(dataset, in: workingDirectory, fileManager: fileManager)

            let training = MLSoundClassifier.DataSource.filesByLabel(filesByLabel(snapshot, split: .training))
            let validation = MLSoundClassifier.DataSource.filesByLabel(filesByLabel(snapshot, split: .validation))
            let parameters = MLSoundClassifier.ModelParameters(
                validation: .dataSource(validation),
                maxIterations: recipe.maxIterations,
                overlapFactor: recipe.overlapFactor,
                algorithm: .transferLearning(
                    featureExtractor: .audioFeaturePrint(type: .sound, revision: 1),
                    classifier: .logisticRegressor
                ),
                featureExtractionTimeWindowSize: recipe.featureExtractionTimeWindowSeconds
            )
            let classifier = try MLSoundClassifier(trainingData: training, parameters: parameters)
            let testing = MLSoundClassifier.DataSource.filesByLabel(filesByLabel(snapshot, split: .testing))
            let metrics = classifier.evaluation(on: testing)
            guard metrics.isValid, metrics.classificationError.isFinite else {
                throw WakeModelTrainingError.invalidMetrics
            }

            let expectedLabels = Set(WakeDatasetLabel.allCases.map(\.rawValue))
            var falseAccepts = 0
            var falseRejects = 0
            for example in testExamples(snapshot) {
                let predictions = try classifier.predictions(
                    from: [example.url],
                    overlapFactor: recipe.overlapFactor,
                    predictionTimeWindowSize: recipe.featureExtractionTimeWindowSeconds
                )
                guard !predictions.isEmpty, predictions.allSatisfy(expectedLabels.contains) else {
                    throw WakeModelTrainingError.predictionCountMismatch
                }
                if example.label == .background {
                    falseAccepts += predictions.filter { $0 == WakeDatasetLabel.wake.rawValue }.count
                } else if !predictions.contains(WakeDatasetLabel.wake.rawValue) {
                    falseRejects += 1
                }
            }

            let output = outputDirectory.standardizedFileURL
            guard !fileManager.fileExists(atPath: output.path) else {
                throw WakeModelTrainingError.outputAlreadyExists
            }
            let parent = output.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let temporaryDirectory = parent.appendingPathComponent(".conatus-export-\(UUID().uuidString)")
            try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
            do {
                let temporaryModel = temporaryDirectory.appendingPathComponent(recipe.modelFileName)
                let temporaryManifest = temporaryDirectory.appendingPathComponent("HeyConatus.manifest.json")
                try classifier.write(to: temporaryModel)

                let modelData = try Data(contentsOf: temporaryModel)
                let runtimeManifest = try makeRuntimeManifest(
                    dataset: dataset,
                    recipe: recipe,
                    modelData: modelData,
                    falseAccepts: falseAccepts,
                    falseRejects: falseRejects,
                    evaluationHardwareModels: evaluationHardwareModels
                )
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                let manifestData = try encoder.encode(runtimeManifest)
                _ = try WakeModelVerifier.verify(
                    manifestData: manifestData,
                    modelData: modelData,
                    expectedModelFileName: recipe.modelFileName
                )
                try manifestData.write(to: temporaryManifest, options: .atomic)
                try fileManager.moveItem(at: temporaryDirectory, to: output)
            } catch {
                let originalError = error
                do {
                    if fileManager.fileExists(atPath: temporaryDirectory.path) {
                        try fileManager.removeItem(at: temporaryDirectory)
                    }
                } catch {
                    throw WakeModelTrainingError.temporaryCleanupFailed
                }
                throw originalError
            }
            return WakeModelTrainingResult(
                modelURL: output.appendingPathComponent(recipe.modelFileName),
                manifestURL: output.appendingPathComponent("HeyConatus.manifest.json"),
                falseAccepts: falseAccepts,
                falseRejects: falseRejects
            )
        }
    }

    private func withPrivateSnapshot<T>(
        _ body: (URL, FileManager) throws -> T
    ) throws -> T {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("conatus-wake-training-\(UUID().uuidString)")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: false)
        let outcome: Result<T, any Error>
        do {
            outcome = .success(try body(directory, fileManager))
        } catch {
            outcome = .failure(error)
        }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw WakeModelTrainingError.temporaryCleanupFailed
        }
        return try outcome.get()
    }

    private func filesByLabel(
        _ files: [WakeDatasetSplit: [WakeDatasetLabel: [URL]]],
        split: WakeDatasetSplit
    ) -> [String: [URL]] {
        Dictionary(uniqueKeysWithValues: WakeDatasetLabel.allCases.map {
            ($0.rawValue, files[split]?[$0] ?? [])
        })
    }

    private func testExamples(
        _ files: [WakeDatasetSplit: [WakeDatasetLabel: [URL]]]
    ) -> [(url: URL, label: WakeDatasetLabel)] {
        WakeDatasetLabel.allCases.flatMap { label in
            (files[.testing]?[label] ?? []).map { (url: $0, label: label) }
        }
    }

    private func snapshotFiles(
        _ dataset: ValidatedWakeDataset,
        in directory: URL,
        fileManager: FileManager
    ) throws -> [WakeDatasetSplit: [WakeDatasetLabel: [URL]]] {
        var snapshot: [WakeDatasetSplit: [WakeDatasetLabel: [URL]]] = [:]
        for clip in dataset.manifest.clips {
            let source = dataset.rootURL.appendingPathComponent(clip.relativePath).standardizedFileURL
            guard source.resolvingSymlinksInPath().path == source.path else {
                throw WakeDatasetError.symlinkedFile
            }
            let extensionName = source.pathExtension.isEmpty ? "audio" : source.pathExtension
            let destination = directory.appendingPathComponent("\(clip.clipID).\(extensionName)")
            try fileManager.copyItem(at: source, to: destination)
            guard try WakeDatasetValidator.sha256(destination) == clip.sha256 else {
                throw WakeDatasetError.digestMismatch
            }
            snapshot[clip.split, default: [:]][clip.label, default: []].append(destination)
        }
        return snapshot.mapValues { labels in
            labels.mapValues { $0.sorted { $0.path < $1.path } }
        }
    }

    private func makeRuntimeManifest(
        dataset: ValidatedWakeDataset,
        recipe: WakeTrainingRecipe,
        modelData: Data,
        falseAccepts: Int,
        falseRejects: Int,
        evaluationHardwareModels: [String]
    ) throws -> WakeModelManifest {
        let sourcesByID = Dictionary(grouping: dataset.manifest.clips, by: \.sourceID)
        let sourceLicenses = Dictionary(uniqueKeysWithValues: dataset.manifest.sources.map {
            ($0.sourceID, $0.licenseIdentifier)
        })
        let sources = sourcesByID.keys.sorted().map { sourceID in
            let clips = sourcesByID[sourceID, default: []]
            let material = clips.sorted { $0.clipID < $1.clipID }
                .map { "\($0.clipID)\t\($0.sha256)" }.joined(separator: "\n")
            let digest = SHA256.hash(data: Data(material.utf8))
                .map { String(format: "%02x", $0) }.joined()
            return WakeTrainingDataSource(
                sourceID: sourceID,
                licenseIdentifier: sourceLicenses[sourceID, default: ""],
                contentSHA256: digest,
                sampleCount: clips.count
            )
        }
        let testingWake = dataset.manifest.clips.filter {
            $0.split == .testing && $0.label == .wake
        }
        let negativeMilliseconds = dataset.manifest.clips.filter {
            $0.split == .testing && $0.label == .background
        }.reduce(0) { $0 + $1.durationMilliseconds }
        let testingSourceIDs = Set(dataset.manifest.clips.compactMap {
            $0.split == .testing ? $0.sourceID : nil
        })
        let accentTags = Set(dataset.manifest.sources.filter {
            testingSourceIDs.contains($0.sourceID)
        }.flatMap(\.accentTags)).sorted()
        let modelDigest = SHA256.hash(data: modelData)
            .map { String(format: "%02x", $0) }.joined()

        return WakeModelManifest(
            schemaVersion: 1,
            modelFileName: recipe.modelFileName,
            modelSHA256: modelDigest,
            modelLicenseIdentifier: recipe.modelLicenseIdentifier,
            distributionApprovalReference: dataset.manifest.distributionApprovalReference,
            wakeLabel: WakeDatasetLabel.wake.rawValue,
            backgroundLabel: WakeDatasetLabel.background.rawValue,
            sampleRate: dataset.manifest.clips[0].sampleRate,
            trainingRecipeSHA256: try recipe.sha256(),
            trainingDataSources: sources,
            evaluation: WakeModelEvaluation(
                corpusSHA256: dataset.corpusSHA256,
                positiveCount: testingWake.count,
                negativeMinutes: negativeMilliseconds / 60_000,
                falseAccepts: falseAccepts,
                falseRejects: falseRejects,
                accentTags: accentTags,
                hardwareModels: evaluationHardwareModels.sorted()
            )
        )
    }
}
