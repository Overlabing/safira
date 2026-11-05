// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// Whether a link that is already open in the Target profile focuses its Matching tab instead of opening a new Tab. On
/// until the user turns it off; one choice for the whole app, not one per Profile.
public struct MatchingTabSettings: Hashable, Sendable, Codable {
    public var isEnabled: Bool

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    public static let title = String(localized: "Focus an Open Tab Instead of Opening a Duplicate", table: "LinkRouting", bundle: .module,
                                     comment: "Menu item and Defaults title")

    public static let explanation = String(localized: """
        When a link from another app is already open as a Tab of the Profile that receives it, in any Space, Safira \
        shows that Tab instead of opening a new one, and a banner offers to open the link in a new Tab anyway. \
        Addresses compare without letter case in the scheme and host, trailing slash, fragment and tracking \
        parameters. A Link rule can force a new Tab. The Link picker also marks the Profiles where the link is open. \
        Turned off, every link opens a new Tab.
        """, table: "LinkRouting", bundle: .module, comment: "Defaults: explanation of focusing a Matching tab")

    /// The entry this type contributes to the registry of defaults, with the value of a fresh `MatchingTabSettings`.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "linkMatching.focusOpenTab",
                title: title,
                value: DefaultWording.onOff(MatchingTabSettings().isEnabled),
                explanation: explanation,
                whereToChange: DefaultWording.safiraMenu,
                control: .toggle(isOn: MatchingTabSettings().isEnabled)
            ),
        ]
    }
}

/// Keeps the setting across launches.
public struct MatchingTabSettingsStore: @unchecked Sendable {
    private static let key = "linkMatching.focusOpenTab"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> MatchingTabSettings {
        MatchingTabSettings(isEnabled: defaults.object(forKey: Self.key) as? Bool ?? MatchingTabSettings().isEnabled)
    }

    public func save(_ settings: MatchingTabSettings) {
        defaults.set(settings.isEnabled, forKey: Self.key)
    }
}
