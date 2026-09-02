// swift-tools-version: 6.0
// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "ConatusMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ConatusMac", targets: ["ConatusMac"]),
        .executable(name: "ConatusWakeModelTool", targets: ["ConatusWakeModelTool"]),
        .library(name: "ConatusContracts", targets: ["ConatusContracts"]),
        .library(name: "ConatusCommandCenter", targets: ["ConatusCommandCenter"]),
        .library(name: "ConatusVoice", targets: ["ConatusVoice"]),
        .library(name: "ConatusVoicePlatform", targets: ["ConatusVoicePlatform"]),
        .library(name: "ConatusWakeCollection", targets: ["ConatusWakeCollection"]),
        .library(name: "ConatusWakeModelTraining", targets: ["ConatusWakeModelTraining"]),
    ],
    dependencies: [
        .package(path: "../../packages/mac-runtime"),
    ],
    targets: [
        .executableTarget(
            name: "ConatusMac",
            dependencies: [
                "ConatusContracts",
                "ConatusCommandCenter",
                .product(name: "ConatusMacRuntime", package: "mac-runtime"),
            ]
        ),
        .target(name: "ConatusContracts"),
        .target(name: "ConatusCommandCenter", dependencies: ["ConatusContracts", "ConatusVoice"]),
        .target(name: "ConatusVoice", dependencies: ["ConatusContracts"]),
        .target(name: "ConatusVoicePlatform", dependencies: ["ConatusContracts", "ConatusVoice"]),
        .target(name: "ConatusWakeCollection"),
        .target(name: "ConatusWakeModelTraining", dependencies: ["ConatusVoicePlatform"]),
        .executableTarget(name: "ConatusWakeModelTool", dependencies: ["ConatusWakeModelTraining"]),
        .testTarget(name: "ConatusContractsTests", dependencies: ["ConatusContracts"]),
        .testTarget(name: "ConatusCommandCenterTests", dependencies: ["ConatusCommandCenter"]),
        .testTarget(name: "ConatusVoiceTests", dependencies: ["ConatusVoice"]),
        .testTarget(name: "ConatusVoicePlatformTests", dependencies: ["ConatusVoicePlatform"]),
        .testTarget(name: "ConatusWakeCollectionTests", dependencies: ["ConatusWakeCollection"]),
        .testTarget(name: "ConatusWakeModelTrainingTests", dependencies: ["ConatusWakeModelTraining"]),
    ]
)
