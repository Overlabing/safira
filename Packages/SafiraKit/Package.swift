// swift-tools-version: 6.4
// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin
import PackageDescription

// Dependency direction: docs/architecture-v1.md §2.1. Only SafiraWeb links WebKit.
let package = Package(
    name: "SafiraKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SafiraCore", targets: ["SafiraCore"]),
        .library(name: "SafiraStore", targets: ["SafiraStore"]),
        .library(name: "SafiraSession", targets: ["SafiraSession"]),
        .library(name: "SafiraWeb", targets: ["SafiraWeb"]),
        .library(name: "Commands", targets: ["Commands"]),
        .library(name: "LinkRouting", targets: ["LinkRouting"]),
        .library(name: "LinkPickerUI", targets: ["LinkPickerUI"]),
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
        .library(name: "Onboarding", targets: ["Onboarding"]),
        .library(name: "Appearance", targets: ["Appearance"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        .package(url: "https://github.com/Overlabing/ThemeKit", exact: "0.1.0"),
    ],
    targets: [
        .target(name: "SafiraCore"),
        .target(name: "Appearance", dependencies: [
            "SafiraCore",
            .product(name: "ColorCore", package: "ThemeKit"),
            .product(name: "ColorPlatform", package: "ThemeKit"),
        ]),
        .testTarget(name: "AppearanceTests", dependencies: [
            "Appearance", "SafiraCore",
            .product(name: "ColorCore", package: "ThemeKit"),
            .product(name: "ColorPlatform", package: "ThemeKit"),
        ]),
        .testTarget(name: "SafiraCoreTests", dependencies: ["SafiraCore"]),
        .target(name: "SafiraStore", dependencies: ["SafiraCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "SafiraStoreTests", dependencies: [
            "SafiraStore", "SafiraCore", .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .target(name: "SafiraSession", dependencies: ["SafiraCore", "SafiraStore", "Diagnostics", "Appearance"]),
        .testTarget(name: "SafiraSessionTests", dependencies: ["SafiraSession", "SafiraStore", "Diagnostics"]),
        .target(name: "SafiraWeb", dependencies: ["SafiraCore", "SafiraStore", "SafiraSession", "Diagnostics", "Appearance"]),
        .testTarget(name: "SafiraWebTests", dependencies: [
            "SafiraWeb", "SafiraStore", "SafiraSession", "SafiraCore", "Diagnostics",
        ]),
        .target(name: "Commands", dependencies: ["SafiraCore"], resources: [.copy("Presets")]),
        .testTarget(name: "CommandsTests", dependencies: ["Commands"]),
        .target(name: "LinkRouting", dependencies: ["SafiraCore"]),
        .testTarget(name: "LinkRoutingTests", dependencies: ["LinkRouting", "SafiraCore"]),
        .target(name: "LinkPickerUI", dependencies: ["LinkRouting", "SafiraCore"]),
        .testTarget(name: "LinkPickerUITests", dependencies: ["LinkPickerUI", "LinkRouting", "SafiraCore"]),
        .target(name: "Diagnostics", dependencies: ["SafiraCore"]),
        .testTarget(name: "DiagnosticsTests", dependencies: ["Diagnostics", "SafiraCore"]),
        .target(name: "Onboarding", dependencies: ["SafiraCore", "Commands", "LinkRouting", "Diagnostics"]),
        .testTarget(name: "OnboardingTests", dependencies: ["Onboarding", "Commands", "SafiraCore"]),
    ]
)
