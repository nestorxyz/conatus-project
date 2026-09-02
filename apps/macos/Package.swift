// swift-tools-version: 6.0
// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "ConatusMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ConatusMac", targets: ["ConatusMac"]),
        .library(name: "ConatusContracts", targets: ["ConatusContracts"]),
        .library(name: "ConatusCommandCenter", targets: ["ConatusCommandCenter"]),
        .library(name: "ConatusVoice", targets: ["ConatusVoice"]),
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
        .target(name: "ConatusCommandCenter"),
        .target(name: "ConatusVoice", dependencies: ["ConatusContracts"]),
        .testTarget(name: "ConatusContractsTests", dependencies: ["ConatusContracts"]),
        .testTarget(name: "ConatusCommandCenterTests", dependencies: ["ConatusCommandCenter"]),
        .testTarget(name: "ConatusVoiceTests", dependencies: ["ConatusVoice"]),
    ]
)
