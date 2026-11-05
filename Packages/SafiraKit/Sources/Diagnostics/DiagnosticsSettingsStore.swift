// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Preferences
import SafiraCore

/// Keeps the Debug mode choice across launches.
public struct DiagnosticsSettingsStore: Sendable {
    public static let key = "diagnostics.debugMode"
    /// Until AppSupportKit, a plain Boolean.
    public static let legacy = LegacyPreference(key: key, as: DiagnosticsSettings.self) {
        LegacyPreference.bool($0).map { DiagnosticsSettings(isDebugModeEnabled: $0) }
    }
    private let preference: Preference<DiagnosticsSettings>

    public init(store: any KeyValueStore = UserDefaults.standard) {
        preference = Preference(key: Self.key, defaultValue: DiagnosticsSettings(), store: store)
    }

    public func load(unreadable: (PreferenceError) -> Void) -> DiagnosticsSettings {
        preference.loadRestoringDefault(unreadable)
    }

    public func save(_ settings: DiagnosticsSettings) {
        try? preference.save(settings)
    }
}
