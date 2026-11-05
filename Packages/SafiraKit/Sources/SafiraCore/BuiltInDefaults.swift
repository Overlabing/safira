// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// Whether Safira looks for updates by itself. Sparkle keeps the choice; this type only declares the default.
public enum UpdateSettings {
    public static let automaticChecksTitle = String(localized: "Check for Updates Automatically", table: "SafiraCore",
                                                    bundle: .module, comment: "Menu item and Defaults title")
    public static let automaticChecksExplanation = String(localized: """
        Safira does not contact its update server until you choose Check for Updates, or turn this on. \
        Turned on, it checks in the background.
        """, table: "SafiraCore", bundle: .module, comment: "Defaults: explanation of automatic update checks")

    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "updates.automaticChecks",
                title: automaticChecksTitle,
                value: DefaultWording.onOff(false),
                explanation: automaticChecksExplanation,
                whereToChange: DefaultWording.safiraMenu,
                control: .toggle(isOn: false)
            ),
        ]
    }
}

/// The defaults that are facts about how Safira behaves, with no switch in this version. Each is declared so that the
/// user is told about it; the one that is a reminder has nothing to change.
public enum BuiltInDefaults {
    public static let notAdjustable = String(localized: "Not adjustable yet", table: "SafiraCore", bundle: .module,
                                             comment: "Defaults: where to change a default that has no switch yet")

    public static var entries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "privacy.telemetry",
                title: String(localized: "Telemetry", table: "SafiraCore", bundle: .module, comment: "Defaults: entry title"),
                value: String(localized: "None", table: "SafiraCore", bundle: .module, comment: "Defaults: value of Telemetry"),
                explanation: String(localized: """
                    Safira collects no usage data and has no analytics. Nothing is sent without an action of yours: \
                    a page you open, a search you submit, an update check you ask for, a log you export.
                    """, table: "SafiraCore", bundle: .module, comment: "Defaults: explanation of Telemetry"),
                whereToChange: String(localized: "Nothing to change", table: "SafiraCore", bundle: .module,
                                      comment: "Defaults: where to change Telemetry, which is a reminder")
            ),
            DefaultEntry(
                id: "search.remoteSuggestions",
                title: String(localized: "Remote search suggestions", table: "SafiraCore", bundle: .module,
                              comment: "Defaults: entry title"),
                value: String(localized: "Off, local suggestions on", table: "SafiraCore", bundle: .module,
                              comment: "Defaults: value of Remote search suggestions"),
                explanation: String(localized: """
                    What you type in the Command bar is not sent to a search engine to complete it. \
                    Suggestions come from the Active profile's history and open Tabs, on this Mac.
                    """, table: "SafiraCore", bundle: .module, comment: "Defaults: explanation of Remote search suggestions"),
                whereToChange: notAdjustable
            ),
            DefaultEntry(
                id: "web.httpsFirst",
                title: String(localized: "HTTPS first", table: "SafiraCore", bundle: .module, comment: "Defaults: entry title"),
                value: DefaultWording.onOff(true),
                explanation: String(localized: """
                    An address typed without a scheme is tried over HTTPS. When the site offers no secure connection, \
                    Safira warns you before loading it over HTTP, and loads it only if you agree.
                    """, table: "SafiraCore", bundle: .module, comment: "Defaults: explanation of HTTPS first"),
                whereToChange: notAdjustable
            ),
            DefaultEntry(
                id: "session.lazyRestoration",
                title: String(localized: "Restore Tabs lazily", table: "SafiraCore", bundle: .module,
                              comment: "Defaults: entry title"),
                value: DefaultWording.onOff(true),
                explanation: String(localized: """
                    At launch only the selected Tab and the Pinned tabs of the Active profile load, which contacts \
                    those sites. Every other Tab comes back without loading until you select it.
                    """, table: "SafiraCore", bundle: .module, comment: "Defaults: explanation of Restore Tabs lazily"),
                whereToChange: notAdjustable
            ),
            DefaultEntry(
                id: "nonWebLinks.confirmation",
                title: String(localized: "Open links to other apps", table: "SafiraCore", bundle: .module,
                              comment: "Defaults: entry title"),
                value: String(localized: "Ask each time", table: "SafiraCore", bundle: .module,
                              comment: "Defaults: value of Open links to other apps"),
                explanation: String(localized: """
                    When a page opens a link that only another app can take, such as mailto: or slack:, Safira names \
                    the app and asks first. You can remember the answer for a Profile and a scheme, and forget it again.
                    """, table: "SafiraCore", bundle: .module, comment: "Defaults: explanation of Open links to other apps"),
                whereToChange: String(localized: "Profiles menu, Site Permissions…", table: "SafiraCore", bundle: .module,
                                      comment: "Defaults: where to change it; a menu and its item")
            ),
            DefaultEntry(
                id: "downloads.folder",
                title: String(localized: "Downloads folder", table: "SafiraCore", bundle: .module, comment: "Defaults: entry title"),
                value: "~/Downloads",
                explanation: String(localized: """
                    Downloaded files go to your Downloads folder, and each Profile keeps its own list of them, which \
                    the Show Downloads command opens.
                    """, table: "SafiraCore", bundle: .module, comment: "Defaults: explanation of Downloads folder"),
                whereToChange: notAdjustable
            ),
            DefaultEntry(
                id: "web.inspector",
                title: String(localized: "Web inspector", table: "SafiraCore", bundle: .module, comment: "Defaults: entry title"),
                value: DefaultWording.onOff(true),
                explanation: String(localized: """
                    Pages can be inspected from the Develop menu of Safari, once Safari's Develop menu is enabled. \
                    Safira has no inspector of its own.
                    """, table: "SafiraCore", bundle: .module, comment: "Defaults: explanation of Web inspector"),
                whereToChange: String(localized: "Safari's Develop menu", table: "SafiraCore", bundle: .module,
                                      comment: "Defaults: where to change Web inspector")
            ),
        ]
    }
}
