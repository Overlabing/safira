// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Preferences
import SafiraCore

/// Debug mode is opt-in: Safira keeps no logs until the user turns it on.
public struct DiagnosticsSettings: Hashable, Sendable, Codable {
    public var isDebugModeEnabled: Bool

    public init(isDebugModeEnabled: Bool = false) {
        self.isDebugModeEnabled = isDebugModeEnabled
    }

    public static let debugModeTitle = String(localized: "Debug mode", table: "Diagnostics", bundle: .module,
                                              comment: "Defaults: entry title")

    public static let debugModeExplanation = String(
        localized: "Logs stay on this Mac, masked to site hosts, and leave it only through a manual export.",
        table: "Diagnostics", bundle: .module, comment: "Defaults: explanation of Debug mode")

    /// The entry this type contributes to the registry of defaults, with the value of a fresh `DiagnosticsSettings`.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "diagnostics.debugMode",
                title: debugModeTitle,
                value: DefaultWording.onOff(DiagnosticsSettings().isDebugModeEnabled),
                explanation: debugModeExplanation,
                whereToChange: DefaultWording.helpMenu,
                control: .toggle(isOn: DiagnosticsSettings().isDebugModeEnabled)
            ),
        ]
    }
}
