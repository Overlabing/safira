// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Diagnostics
import LinkRouting
import SafiraCore

/// Every default Safira makes for the user, declared once (docs/architecture-v1.md §7.2). Onboarding and the Defaults
/// window render this list; a test asserts it against the documented values.
public enum DefaultsRegistry {
    /// In the order the user reads them.
    public static var entries: [DefaultEntry] {
        BuiltInDefaults.entries.filter { $0.id == "privacy.telemetry" }
            + UpdateSettings.defaultEntries
            + SearchEngine.defaultEntries
            + BuiltInDefaults.entries.filter { $0.id == "search.remoteSuggestions" || $0.id == "web.httpsFirst" }
            + DiagnosticsSettings.defaultEntries
            + WebContentSettings.defaultEntries
            + BuiltInDefaults.entries.filter { $0.id == "web.inspector" }
            + MatchingTabSettings.defaultEntries
            + AskForSpaceSettings.defaultEntries
            + LinkChoiceLogSettings.defaultEntries
            + NativeApp.defaultEntries
            + DefaultBrowser.defaultEntries
            + ShortcutPreset.defaultEntries
            + BuiltInDefaults.entries.filter {
                ["session.lazyRestoration", "nonWebLinks.confirmation", "downloads.folder"].contains($0.id)
            }
            + SidebarPresentation.defaultEntries
    }

    /// The entries onboarding and the Defaults window show.
    public static var userFacing: [DefaultEntry] {
        entries.filter(\.isUserFacing)
    }

    public static func entry(_ id: String) -> DefaultEntry? {
        entries.first { $0.id == id }
    }
}
