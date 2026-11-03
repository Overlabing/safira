// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore

/// Debug mode is opt-in: Safira keeps no logs until the user turns it on.
public struct DiagnosticsSettings: Hashable, Sendable, Codable {
    public var isDebugModeEnabled: Bool

    public init(isDebugModeEnabled: Bool = false) {
        self.isDebugModeEnabled = isDebugModeEnabled
    }

    public static let debugModeTitle = "Debug mode"

    public static let debugModeExplanation =
        "Logs stay on this Mac, masked to site hosts, and leave it only through a manual export."

    /// The entry this type contributes to the registry of defaults, with the value of a fresh `DiagnosticsSettings`.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "diagnostics.debugMode",
                title: debugModeTitle,
                value: DiagnosticsSettings().isDebugModeEnabled ? "On" : "Off",
                explanation: debugModeExplanation,
                whereToChange: "Help menu"
            ),
        ]
    }
}
