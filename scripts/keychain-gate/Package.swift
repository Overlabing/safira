// swift-tools-version: 6.4
// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin
import PackageDescription

// The app scripts/keychain-gate.sh signs and runs. It uses SafiraKit's own extension host, not a copy of it.
let package = Package(
    name: "SafiraKeychainGate",
    platforms: [.macOS("27.0")],
    dependencies: [.package(path: "../../Packages/SafiraKit")],
    targets: [
        .executableTarget(name: "SafiraKeychainGate", dependencies: [
            .product(name: "SafiraCore", package: "SafiraKit"),
            .product(name: "SafiraWeb", package: "SafiraKit"),
        ]),
    ]
)
