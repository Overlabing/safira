// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Commands
import Diagnostics
import LinkRouting
import SafiraCore

MainActor.assumeIsolated {
    // Before any store reads: the settings saved before AppSupportKit become the JSON its preferences read.
    if let domain = Bundle.main.bundleIdentifier {
        LegacyPreference.migrate(
            [CompactModeStore.legacy, SidebarSideStore.legacy, DiagnosticsSettingsStore.legacy,
             LinkChoiceLogSettingsStore.legacy, AskForSpaceSettingsStore.legacy, MatchingTabSettingsStore.legacy]
                + ShortcutStore.legacy,
            in: .standard, domain: domain)
    }
    let application = NSApplication.shared
    let delegate = AppDelegate(preferenceProblems: PreferenceProblems())
    application.delegate = delegate
    application.run()
}
