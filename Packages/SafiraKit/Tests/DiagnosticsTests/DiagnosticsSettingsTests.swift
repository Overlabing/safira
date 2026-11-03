// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import SafiraCore
import Testing

@Test func debugModeIsOffUntilTheUserTurnsItOn() {
    #expect(DiagnosticsSettings().isDebugModeEnabled == false)
}

@Test func theRegistryListsDebugModeAsOffAndChangedFromTheHelpMenu() throws {
    let entry = try #require(DiagnosticsSettings.defaultEntries.first)

    #expect(DiagnosticsSettings.defaultEntries.count == 1)
    #expect(entry.id == "diagnostics.debugMode")
    #expect(entry.title == "Debug mode")
    #expect(entry.value == "Off")
    #expect(entry.explanation == "Logs stay on this Mac, masked to site hosts, and leave it only through a manual export.")
    #expect(entry.whereToChange == "Help menu")
}
