// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusWakeModelTraining
import Foundation

@main
enum ConatusWakeModelTool {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--help"] {
            print(Invocation.usage)
            return
        }
        do {
            let invocation = try Invocation(arguments: arguments)
            let manifestData = try Data(contentsOf: invocation.manifestURL)
            let dataset = try WakeDatasetValidator.validate(
                manifestData: manifestData,
                datasetRoot: invocation.datasetRoot
            )
            switch invocation.command {
            case .validate:
                print("Dataset valid: \(dataset.manifest.clips.count) clips; corpus \(dataset.corpusSHA256)")
            case .train:
                guard
                    let outputDirectory = invocation.outputDirectory,
                    let modelLicenseIdentifier = invocation.modelLicenseIdentifier,
                    let evaluationHardwareModel = invocation.evaluationHardwareModel
                else {
                    throw InvocationError.missingTrainingOption
                }
                let result = try WakeModelTrainer().train(
                    dataset: dataset,
                    recipe: WakeTrainingRecipe(modelLicenseIdentifier: modelLicenseIdentifier),
                    outputDirectory: outputDirectory,
                    evaluationHardwareModels: [evaluationHardwareModel]
                )
                print("Candidate model: \(result.modelURL.path)")
                print("Runtime manifest: \(result.manifestURL.path)")
                print("Offline false accepts: \(result.falseAccepts); false rejects: \(result.falseRejects)")
            }
        } catch {
            writeError("Conatus wake-model tool failed: \(String(describing: error))\n")
            writeError(Invocation.usage)
            Foundation.exit(2)
        }
    }

    private static func writeError(_ value: String) {
        FileHandle.standardError.write(Data(value.utf8))
    }
}

private enum Command: String {
    case validate
    case train
}

private enum InvocationError: Error {
    case invalidCommand
    case missingValue(String)
    case duplicateOption(String)
    case unknownOption(String)
    case missingRequiredOption(String)
    case missingTrainingOption
}

private struct Invocation {
    static let usage = """
    Usage:
      ConatusWakeModelTool validate --manifest <json> --dataset-root <external-directory>
      ConatusWakeModelTool train --manifest <json> --dataset-root <external-directory> \\
        --output <directory> --model-license <commercial-license> --hardware-model <identifier>

    This tool never records audio. Dataset collection requires a separate explicit consent flow.
    """

    let command: Command
    let manifestURL: URL
    let datasetRoot: URL
    let outputDirectory: URL?
    let modelLicenseIdentifier: String?
    let evaluationHardwareModel: String?

    init(arguments: [String]) throws {
        guard let commandValue = arguments.first, let command = Command(rawValue: commandValue) else {
            throw InvocationError.invalidCommand
        }
        self.command = command
        var options: [String: String] = [:]
        var index = 1
        while index < arguments.count {
            let option = arguments[index]
            guard option.hasPrefix("--") else { throw InvocationError.unknownOption(option) }
            guard index + 1 < arguments.count else { throw InvocationError.missingValue(option) }
            guard options[option] == nil else { throw InvocationError.duplicateOption(option) }
            options[option] = arguments[index + 1]
            index += 2
        }
        let allowed = Set(["--manifest", "--dataset-root", "--output", "--model-license", "--hardware-model"])
        if let unknown = options.keys.first(where: { !allowed.contains($0) }) {
            throw InvocationError.unknownOption(unknown)
        }
        guard let manifest = options["--manifest"], !manifest.isEmpty else {
            throw InvocationError.missingRequiredOption("--manifest")
        }
        guard let root = options["--dataset-root"], !root.isEmpty else {
            throw InvocationError.missingRequiredOption("--dataset-root")
        }
        manifestURL = URL(fileURLWithPath: manifest)
        datasetRoot = URL(fileURLWithPath: root)
        outputDirectory = options["--output"].map(URL.init(fileURLWithPath:))
        modelLicenseIdentifier = options["--model-license"]
        evaluationHardwareModel = options["--hardware-model"]
        if command == .validate, options.keys.contains(where: {
            ["--output", "--model-license", "--hardware-model"].contains($0)
        }) {
            throw InvocationError.unknownOption("training option for validate")
        }
    }
}
