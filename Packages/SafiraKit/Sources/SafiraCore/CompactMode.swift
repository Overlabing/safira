// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// Whether the Main window shows its sidebar. In Compact mode the sidebar is hidden and the page takes the full width;
/// the sidebar comes back over the page on demand and goes away again. Only `isCompact` is kept across launches:
/// a relaunch always starts with the sidebar hidden, never revealed.
public struct SidebarPresentation: Equatable, Sendable {
    public private(set) var isCompact: Bool
    /// The sidebar is drawn over the page. Always false outside Compact mode.
    public private(set) var isRevealed = false

    public init(isCompact: Bool = false) {
        self.isCompact = isCompact
    }

    /// True when the sidebar is on screen, docked or revealed.
    public var isSidebarShown: Bool { !isCompact || isRevealed }

    public mutating func setCompact(_ isCompact: Bool) {
        self.isCompact = isCompact
        isRevealed = false
    }

    public mutating func toggleCompact() {
        setCompact(!isCompact)
    }

    /// The pointer touched the window's edge on the sidebar's side, or the user used the shortcut. No effect outside Compact mode.
    public mutating func reveal() {
        if isCompact { isRevealed = true }
    }

    /// The pointer left the sidebar, or the keyboard focus went back to the page.
    public mutating func hide() {
        isRevealed = false
    }

    /// The shortcut reveals the sidebar, and hides it when it is already revealed.
    public mutating func toggleRevealed() {
        if isCompact { isRevealed.toggle() }
    }

    public static let compactModeTitle = "Compact Mode"
    public static let compactModeExplanation =
        "The sidebar is hidden and the page uses the full width. Move the pointer to the window's edge on the sidebar's side, or "
        + "use Show Sidebar, to bring it back over the page; it hides again when the pointer leaves it or you go back "
        + "to the page."

    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "window.compactMode",
                title: compactModeTitle,
                value: SidebarPresentation().isCompact ? "On" : "Off",
                explanation: compactModeExplanation,
                whereToChange: "View menu",
                control: .toggle(isOn: SidebarPresentation().isCompact),
                isUserFacing: false
            )
        ]
    }
}

/// Keeps the Compact mode choice across launches, until Profiles persist their settings.
public struct CompactModeStore: @unchecked Sendable {
    private static let key = "window.compactMode"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> SidebarPresentation {
        SidebarPresentation(isCompact: defaults.bool(forKey: Self.key))
    }

    public func save(_ presentation: SidebarPresentation) {
        defaults.set(presentation.isCompact, forKey: Self.key)
    }
}
