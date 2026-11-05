// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// Which side of the window the sidebar sits on, for every window and every Profile. The page takes the other side;
/// in Compact mode the sidebar comes back from the same side.
public enum SidebarSide: String, Sendable, CaseIterable {
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

/// Keeps the side of the sidebar across launches, for the whole app. Anything but "right" reads as the left side, so
/// a missing or damaged value never moves the sidebar.
public struct SidebarSideStore: @unchecked Sendable {
    public static let key = "window.sidebarSide"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> SidebarSide {
        defaults.string(forKey: Self.key) == SidebarSide.right.rawValue ? .right : .left
    }

    public func save(_ side: SidebarSide) {
        defaults.set(side.rawValue, forKey: Self.key)
    }
}
