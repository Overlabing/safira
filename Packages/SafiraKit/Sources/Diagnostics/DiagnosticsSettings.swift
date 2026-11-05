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
        localized: """
            Logs stay on this Mac and leave it only through a manual export. The log file and its export write private \
            values as <private>, so they hold no host, address or page title. The system log always gets the events \
            that name no site, and gets a site's host only while Debug mode is on, masked by macOS.
            """,
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
