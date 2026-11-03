// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// Keeps the Debug mode choice across launches.
public struct DiagnosticsSettingsStore: @unchecked Sendable {
    private static let debugModeKey = "diagnostics.debugMode"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> DiagnosticsSettings {
        DiagnosticsSettings(isDebugModeEnabled: defaults.bool(forKey: Self.debugModeKey))
    }

    public func save(_ settings: DiagnosticsSettings) {
        defaults.set(settings.isDebugModeEnabled, forKey: Self.debugModeKey)
    }
}
