// swift-tools-version: 6.0
// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "ConatusMacRuntime",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ConatusMacRuntime", targets: ["ConatusMacRuntime"]),
        .executable(name: "ConatusFakeProviderFixture", targets: ["ConatusFakeProviderFixture"]),
    ],
    targets: [
        .target(name: "ConatusMacRuntime"),
        .executableTarget(name: "ConatusFakeProviderFixture"),
        .testTarget(name: "ConatusMacRuntimeTests", dependencies: ["ConatusMacRuntime"]),
    ]
)
