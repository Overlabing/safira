// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// Whether Safira looks for updates by itself. Sparkle keeps the choice; this type only declares the default.
public enum UpdateSettings {
    public static let automaticChecksTitle = "Check for Updates Automatically"
    public static let automaticChecksExplanation =
        "Safira does not contact its update server until you choose Check for Updates, or turn this on. "
        + "Turned on, it checks in the background."

    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "updates.automaticChecks",
                title: automaticChecksTitle,
                value: "Off",
                explanation: automaticChecksExplanation,
                whereToChange: "Safira menu",
                control: .toggle(isOn: false)
            ),
        ]
    }
}

/// The defaults that are facts about how Safira behaves, with no switch in this version. Each is declared so that the
/// user is told about it; the one that is a reminder has nothing to change.
public enum BuiltInDefaults {
    public static let notAdjustable = "Not adjustable yet"

    public static var entries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "privacy.telemetry",
                title: "Telemetry",
                value: "None",
                explanation: "Safira collects no usage data and has no analytics. Nothing is sent without an action of "
                    + "yours: a page you open, a search you submit, an update check you ask for, a log you export.",
                whereToChange: "Nothing to change"
            ),
            DefaultEntry(
                id: "search.remoteSuggestions",
                title: "Remote search suggestions",
                value: "Off, local suggestions on",
                explanation: "What you type in the Command bar is not sent to a search engine to complete it. "
                    + "Suggestions come from the Active profile's history and open Tabs, on this Mac.",
                whereToChange: notAdjustable
            ),
            DefaultEntry(
                id: "web.httpsFirst",
                title: "HTTPS first",
                value: "On",
                explanation: "An address typed without a scheme is tried over HTTPS. When the site offers no secure "
                    + "connection, Safira warns you before loading it over HTTP, and loads it only if you agree.",
                whereToChange: notAdjustable
            ),
            DefaultEntry(
                id: "session.lazyRestoration",
                title: "Restore Tabs lazily",
                value: "On",
                explanation: "At launch only the selected Tab and the Pinned tabs of the Active profile load, which "
                    + "contacts those sites. Every other Tab comes back without loading until you select it.",
                whereToChange: notAdjustable
            ),
            DefaultEntry(
                id: "nonWebLinks.confirmation",
                title: "Open links to other apps",
                value: "Ask each time",
                explanation: "When a page opens a link that only another app can take, such as mailto: or slack:, Safira "
                    + "names the app and asks first. You can remember the answer for a Profile and a scheme, and "
                    + "forget it again.",
                whereToChange: "Profiles menu, Site Permissions…"
            ),
            DefaultEntry(
                id: "downloads.folder",
                title: "Downloads folder",
                value: "~/Downloads",
                explanation: "Downloaded files go to your Downloads folder, and each Profile keeps its own list of "
                    + "them, which the Show Downloads command opens.",
                whereToChange: notAdjustable
            ),
            DefaultEntry(
                id: "web.inspector",
                title: "Web inspector",
                value: "On",
                explanation: "Pages can be inspected from the Develop menu of Safari, once Safari's Develop menu is "
                    + "enabled. Safira has no inspector of its own.",
                whereToChange: "Safari's Develop menu"
            ),
        ]
    }
}
