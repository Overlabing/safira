// swift-tools-version: 6.4
// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin
import PackageDescription

// Dependency direction: docs/architecture-v1.md §2.1. Only SafiraWeb links WebKit.
let preferences = Target.Dependency.product(name: "Preferences", package: "AppSupportKit")
let userFacing = Target.Dependency.product(name: "UserFacing", package: "AppSupportKit")
let commandKit = Target.Dependency.product(name: "CommandKit", package: "CommandKit")
let defaultApps = Target.Dependency.product(name: "DefaultApps", package: "AppSupportKit")
let diagnosticsKit = Target.Dependency.product(name: "DiagnosticsKit", package: "DiagnosticsKit")
let appShellKit = Target.Dependency.product(name: "AppShellKit", package: "AppShellKit")
let spaces = Target.Dependency.product(name: "Spaces", package: "AppSupportKit")

let package = Package(
    name: "SafiraKit",
    defaultLocalization: "en",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SafiraCore", targets: ["SafiraCore"]),
        .library(name: "SafiraStore", targets: ["SafiraStore"]),
        .library(name: "SafiraSession", targets: ["SafiraSession"]),
        .library(name: "SafiraWeb", targets: ["SafiraWeb"]),
        .library(name: "Commands", targets: ["Commands"]),
        .library(name: "LinkRouting", targets: ["LinkRouting"]),
        .library(name: "LinkPickerUI", targets: ["LinkPickerUI"]),
        .library(name: "DownloadsUI", targets: ["DownloadsUI"]),
        .library(name: "Diagnostics", targets: ["Diagnostics"]),
        .library(name: "Onboarding", targets: ["Onboarding"]),
        .library(name: "Appearance", targets: ["Appearance"]),
        .library(name: "SafiraSettings", targets: ["SafiraSettings"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        .package(url: "https://github.com/Overlabing/ThemeKit", exact: "0.2.13"),
        .package(url: "https://github.com/Overlabing/AppSupportKit", exact: "0.1.2"),
        .package(url: "https://github.com/Overlabing/CommandKit", exact: "0.1.3"),
        .package(url: "https://github.com/Overlabing/DiagnosticsKit", exact: "0.1.2"),
        .package(url: "https://github.com/Overlabing/AppShellKit", exact: "0.1.0"),
    ],
    targets: [
        .target(name: "SafiraCore", dependencies: [preferences, userFacing, spaces], resources: [.process("Resources")]),
        .target(name: "Appearance", dependencies: [
            "SafiraCore",
            .product(name: "ColorCore", package: "ThemeKit"),
            .product(name: "ColorPlatform", package: "ThemeKit"),
            .product(name: "DesignKit", package: "ThemeKit"),
        ]),
        // Every test window comes from here (scripts/test-window-patterns.txt).
        .target(name: "TestSupport", path: "Tests/TestSupport"),
        .testTarget(name: "TestSupportTests", dependencies: ["TestSupport"]),
        .testTarget(name: "AppearanceTests", dependencies: [
            "Appearance", "SafiraCore", "TestSupport",
            .product(name: "ColorCore", package: "ThemeKit"),
            .product(name: "ColorPlatform", package: "ThemeKit"),
            .product(name: "DesignKit", package: "ThemeKit"),
        ]),
        .testTarget(name: "SafiraCoreTests", dependencies: ["SafiraCore", preferences, userFacing, spaces]),
        .target(name: "SafiraStore", dependencies: ["SafiraCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "SafiraStoreTests", dependencies: [
            "SafiraStore", "SafiraCore", .product(name: "GRDB", package: "GRDB.swift"),
        ]),
        .target(name: "SafiraSession", dependencies: [
            "SafiraCore", "SafiraStore", "Diagnostics", "Appearance",
            .product(name: "SiteIcons", package: "AppSupportKit"),
        ], resources: [.process("Resources")]),
        .testTarget(name: "SafiraSessionTests", dependencies: ["SafiraSession", "SafiraStore", "Diagnostics"]),
        .target(name: "SafiraWeb", dependencies: ["SafiraCore", "SafiraStore", "SafiraSession", "Diagnostics", "Appearance",
                                                diagnosticsKit],
                resources: [.process("Resources")]),
        .testTarget(name: "SafiraWebTests", dependencies: [
            "SafiraWeb", "SafiraStore", "SafiraSession", "SafiraCore", "Diagnostics", "Appearance", diagnosticsKit,
            "TestSupport",
        ]),
        .target(name: "Commands", dependencies: ["SafiraCore", preferences, commandKit],
                resources: [.copy("Presets"), .process("Resources")]),
        .testTarget(name: "CommandsTests", dependencies: ["Commands", "SafiraCore", preferences, commandKit]),
        .target(name: "LinkRouting", dependencies: ["SafiraCore", preferences, defaultApps], resources: [.process("Resources")]),
        .testTarget(name: "LinkRoutingTests", dependencies: ["LinkRouting", "SafiraCore", preferences, defaultApps]),
        .target(name: "LinkPickerUI", dependencies: ["LinkRouting", "SafiraCore"], resources: [.process("Resources")]),
        .testTarget(name: "LinkPickerUITests", dependencies: ["LinkPickerUI", "LinkRouting", "SafiraCore"]),
        .target(name: "DownloadsUI", dependencies: [
            "SafiraCore", "SafiraSession",
            .product(name: "ColorUI", package: "ThemeKit"),
            .product(name: "DesignKit", package: "ThemeKit"),
        ], resources: [.process("Resources")]),
        .testTarget(name: "DownloadsUITests", dependencies: [
            "DownloadsUI", "SafiraCore", "SafiraSession",
            .product(name: "ColorCore", package: "ThemeKit"),
            .product(name: "ColorUI", package: "ThemeKit"),
            .product(name: "DesignKit", package: "ThemeKit"),
        ]),
        .target(name: "Diagnostics", dependencies: ["SafiraCore", preferences, diagnosticsKit],
                resources: [.process("Resources")]),
        .testTarget(name: "DiagnosticsTests", dependencies: ["Diagnostics", "SafiraCore", preferences, diagnosticsKit]),
        .target(name: "Onboarding", dependencies: ["SafiraCore", "Commands", "LinkRouting", "Diagnostics", preferences],
                resources: [.process("Resources")]),
        .testTarget(name: "OnboardingTests", dependencies: ["Onboarding", "Commands", "SafiraCore", preferences]),
        .target(name: "SafiraSettings", dependencies: ["SafiraCore", "SafiraSession", "Appearance", "Commands", appShellKit,
                                                preferences, spaces],
                resources: [.process("Resources")]),
        .testTarget(name: "SafiraSettingsTests", dependencies: ["SafiraSettings", "Commands", "Onboarding", "SafiraCore",
                                                             "SafiraSession", appShellKit, preferences, spaces]),
    ]
)
