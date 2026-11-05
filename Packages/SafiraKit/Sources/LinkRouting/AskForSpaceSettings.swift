// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Preferences
import SafiraCore

/// Whether the Link picker asks for the Space after the Profile. Off until the user turns it on: without it a link
/// opens in the Profile's last active Space.
public struct AskForSpaceSettings: Hashable, Sendable, Codable {
    public var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public static let title = String(localized: "Ask for the Space Too", table: "LinkRouting", bundle: .module, comment: "Menu item and Defaults title")

    public static let explanation = String(localized: """
        After you choose a Profile for a link, the Link picker also asks which of its Spaces receives it. A Link rule \
        can still name a Space, and then nothing is asked.
        """, table: "LinkRouting", bundle: .module, comment: "Defaults: explanation of Ask for the Space Too")

    /// The entry this type contributes to the registry of defaults, with the value of a fresh `AskForSpaceSettings`.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "linkPicker.askForSpace",
                title: title,
                value: DefaultWording.onOff(AskForSpaceSettings().isEnabled),
                explanation: explanation,
                whereToChange: DefaultWording.safiraMenu,
                control: .toggle(isOn: AskForSpaceSettings().isEnabled)
            ),
        ]
    }
}

/// Keeps the setting across launches.
public struct AskForSpaceSettingsStore: Sendable {
    public static let key = "linkPicker.askForSpace"
    /// Until AppSupportKit, a plain Boolean.
    public static let legacy = LegacyPreference(key: key, as: AskForSpaceSettings.self) {
        LegacyPreference.bool($0).map { AskForSpaceSettings(isEnabled: $0) }
    }
    private let preference: Preference<AskForSpaceSettings>

    public init(store: any KeyValueStore = UserDefaults.standard) {
        preference = Preference(key: Self.key, defaultValue: AskForSpaceSettings(), store: store)
    }

    public func load(unreadable: (PreferenceError) -> Void) -> AskForSpaceSettings {
        preference.loadRestoringDefault(unreadable)
    }

    public func save(_ settings: AskForSpaceSettings) {
        try? preference.save(settings)
    }
}

extension NativeApp {
    /// The entry for links that open in an installed Slack, Linear, Notion or Figma.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "linkRules.nativeApps",
                title: String(localized: "Open Slack, Linear, Notion and Figma links in their apps", table: "LinkRouting", bundle: .module,
                              comment: "Defaults: entry title"),
                value: String(localized: "On, when the app is installed", table: "LinkRouting", bundle: .module,
                              comment: "Defaults: value of opening links in native apps"),
                explanation: String(localized: """
                    These links skip the Link rules and the Link picker. A Slack link also needs the Slack folder \
                    granted in the Safira menu; without it the link goes to the rules or the Link picker. Each app \
                    can be turned off in the rules file.
                    """, table: "LinkRouting", bundle: .module, comment: "Defaults: explanation of opening links in native apps"),
                whereToChange: String(localized: "Rules file", table: "LinkRouting", bundle: .module, comment: "Defaults: where to change it, the Link rules file")
            ),
        ]
    }
}
