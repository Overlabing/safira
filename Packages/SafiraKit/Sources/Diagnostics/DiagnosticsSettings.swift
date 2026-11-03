// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// Debug mode is opt-in: Safira keeps no logs until the user turns it on.
public struct DiagnosticsSettings: Hashable, Sendable, Codable {
    public var isDebugModeEnabled: Bool

    public init(isDebugModeEnabled: Bool = false) {
        self.isDebugModeEnabled = isDebugModeEnabled
    }
}
