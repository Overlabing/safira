// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Preferences

/// Which side of the window the sidebar sits on, for every window and every Profile. The page takes the other side;
/// in Compact mode the sidebar comes back from the same side.
public enum SidebarSide: String, Sendable, CaseIterable, Codable {
    case left
    case right

    public static let title = String(localized: "Sidebar on the Right", table: "SafiraCore", bundle: .module,
                                     comment: "Menu item and Defaults title")
    public static let explanation = String(localized: """
        The sidebar, with the address and the Tabs, sits on the left of the window. Put it on the right instead; in \
        Compact mode it then comes back from the right edge.
        """, table: "SafiraCore", bundle: .module, comment: "Defaults: explanation of Sidebar on the Right")

    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: SidebarSideStore.key,
                title: title,
                value: String(localized: "Off, on the left", table: "SafiraCore", bundle: .module,
                              comment: "Defaults: value of Sidebar on the Right"),
                explanation: explanation,
                whereToChange: String(localized: "View menu, or Safira menu, Defaults…", table: "SafiraCore",
                                      bundle: .module, comment: "Defaults: where to change Sidebar on the Right"),
                control: .toggle(isOn: false)
            ),
        ]
    }
}

/// Keeps the side of the sidebar across launches, for the whole app. A missing or damaged value reads as the left side,
/// so it never moves the sidebar.
public struct SidebarSideStore: Sendable {
    public static let key = "window.sidebarSide"
    /// Until AppSupportKit, the side's name as plain text; anything but "right" was the left side.
    public static let legacy = LegacyPreference(key: key, as: SidebarSide.self) {
        ($0 as? String) == SidebarSide.right.rawValue ? SidebarSide.right : .left
    }
    private let preference: Preference<SidebarSide>

    public init(store: any KeyValueStore = UserDefaults.standard) {
        preference = Preference(key: Self.key, defaultValue: .left, store: store)
    }

    public func load(unreadable: (PreferenceError) -> Void) -> SidebarSide {
        preference.loadRestoringDefault(unreadable)
    }

    public func save(_ side: SidebarSide) {
        try? preference.save(side)
    }
}
