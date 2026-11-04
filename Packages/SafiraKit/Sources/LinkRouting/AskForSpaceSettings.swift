// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// Whether the Link picker asks for the Space after the Profile. Off until the user turns it on: without it a link
/// opens in the Profile's last active Space.
public struct AskForSpaceSettings: Hashable, Sendable, Codable {
    public var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public static let title = "Ask for the Space Too"

    public static let explanation =
        "After you choose a Profile for a link, the Link picker also asks which of its Spaces receives it. A Link rule "
        + "can still name a Space, and then nothing is asked."

    /// The entry this type contributes to the registry of defaults, with the value of a fresh `AskForSpaceSettings`.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "linkPicker.askForSpace",
                title: title,
                value: AskForSpaceSettings().isEnabled ? "On" : "Off",
                explanation: explanation,
                whereToChange: "Safira menu"
            ),
        ]
    }
}

/// Keeps the setting across launches.
public struct AskForSpaceSettingsStore: @unchecked Sendable {
    private static let key = "linkPicker.askForSpace"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AskForSpaceSettings {
        AskForSpaceSettings(isEnabled: defaults.bool(forKey: Self.key))
    }

    public func save(_ settings: AskForSpaceSettings) {
        defaults.set(settings.isEnabled, forKey: Self.key)
    }
}

extension NativeApp {
    /// The entry for links that open in an installed Slack, Linear, Notion or Figma.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "linkRules.nativeApps",
                title: "Open Slack, Linear, Notion and Figma links in their apps",
                value: "On, when the app is installed",
                explanation: "These links skip the Link rules and the Link picker. A Slack link also needs the Slack "
                    + "folder granted in the Safira menu; without it the link goes to the rules or the Link picker. "
                    + "Each app can be turned off in the rules file.",
                whereToChange: "Rules file"
            ),
        ]
    }
}
