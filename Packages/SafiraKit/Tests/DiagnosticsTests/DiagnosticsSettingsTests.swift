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
    #expect(entry.explanation == """
        Logs stay on this Mac and leave it only through a manual export. The log file and its export write private \
        values as <private>, so they hold no host, address or page title. The system log always gets the events that \
        name no site, and gets a site's host only while Debug mode is on, masked by macOS.
        """)
    #expect(entry.whereToChange == "Help menu")
}
