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
    ],
    targets: [
        .executableTarget(name: "ConatusMac", dependencies: ["ConatusContracts"]),
        .target(name: "ConatusContracts"),
        .testTarget(name: "ConatusContractsTests", dependencies: ["ConatusContracts"]),
    ]
)
