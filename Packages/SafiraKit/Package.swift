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
    ],
    targets: [
        .target(name: "SafiraCore"),
        .testTarget(name: "SafiraCoreTests", dependencies: ["SafiraCore"]),
        .target(name: "SafiraStore", dependencies: ["SafiraCore"]),
        .testTarget(name: "SafiraStoreTests", dependencies: ["SafiraStore", "SafiraCore"]),
        .target(name: "SafiraSession", dependencies: ["SafiraCore", "SafiraStore", "Diagnostics"]),
        .testTarget(name: "SafiraSessionTests", dependencies: ["SafiraSession", "Diagnostics"]),
        .target(name: "SafiraWeb", dependencies: ["SafiraCore", "SafiraSession", "Diagnostics"]),
        .testTarget(name: "SafiraWebTests", dependencies: ["SafiraWeb", "SafiraCore", "Diagnostics"]),
        .target(name: "Commands", dependencies: ["SafiraCore"]),
        .testTarget(name: "CommandsTests", dependencies: ["Commands"]),
        .target(name: "LinkRouting", dependencies: ["SafiraCore"]),
        .testTarget(name: "LinkRoutingTests", dependencies: ["LinkRouting"]),
        .target(name: "LinkPickerUI", dependencies: ["LinkRouting"]),
        .testTarget(name: "LinkPickerUITests", dependencies: ["LinkPickerUI"]),
        .target(name: "Diagnostics", dependencies: ["SafiraCore"]),
        .testTarget(name: "DiagnosticsTests", dependencies: ["Diagnostics", "SafiraCore"]),
        .target(name: "Onboarding", dependencies: ["SafiraCore", "SafiraStore", "Commands"]),
        .testTarget(name: "OnboardingTests", dependencies: ["Onboarding", "Commands"]),
    ]
)
