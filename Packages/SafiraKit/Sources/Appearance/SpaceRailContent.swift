// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import ColorCore
import DesignKit
import Foundation
import SafiraCore

/// What Safira hands ThemeKit's Space rail: every Profile in its order with its Spaces, each Space's glyph, Theme and
/// shortcut. The rail speaks in strings; a Space or Profile goes in and comes back as its UUID string.
public enum SpaceRailContent {
    /// The keys a menu item shows in the bindings in force ("⌃1", "⌃⌥⌘→"); nil where a command has none.
    public struct Shortcuts: Sendable {
        /// ⌃1…⌃9 in order: the active Profile's first nine Spaces.
        public var spaces: [String?]
        public var previousProfile: String?
        public var nextProfile: String?

        public init(spaces: [String?] = [], previousProfile: String? = nil, nextProfile: String? = nil) {
            self.spaces = spaces
            self.previousProfile = previousProfile
            self.nextProfile = nextProfile
        }
    }

    /// Every Profile for the rail. Only the active Profile's Spaces carry ⌃1…⌃9, since those keys reach the active
    /// Profile alone. The Profile right after the active one shows Show Next Profile's key, the one right before it
    /// Show Previous Profile's; with two Profiles the other one is both, and shows the next key.
    public static func profiles(
        _ profiles: [Profile], activeID: ProfileID, spaces: (ProfileID) -> ProfileSpaces, shortcuts: Shortcuts
    ) -> [SpaceRailProfile] {
        let activeIndex = profiles.firstIndex { $0.id == activeID }
        return profiles.enumerated().map { index, profile in
            let isActive = profile.id == activeID
            let profileTheme = ThemeCatalog.theme(id: profile.paletteID, fallback: ThemeCatalog.first)
            let summary = spaces(profile.id)
            let railSpaces = summary.spaces.enumerated().map { position, space in
                SpaceRailSpace(
                    id: space.id.rawValue.uuidString, name: space.name, glyph: glyph(for: space),
                    theme: ThemeCatalog.theme(id: space.paletteID, fallback: profileTheme),
                    shortcut: isActive && position < shortcuts.spaces.count ? shortcuts.spaces[position] : nil)
            }
            return SpaceRailProfile(
                id: profile.id.rawValue.uuidString, name: profile.name, emoji: profile.symbol, spaces: railSpaces,
                lastSpaceID: summary.lastSpaceID?.rawValue.uuidString,
                shortcut: activeIndex.flatMap { profileShortcut(at: index, active: $0, count: profiles.count, shortcuts) })
        }
    }

    /// A Space shows its emoji; a Space with none its initial.
    public static func glyph(for space: SpaceSummary) -> SpaceRailGlyph {
        let emoji = space.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return emoji.isEmpty ? .initial : .emoji(emoji)
    }

    private static func profileShortcut(at index: Int, active: Int, count: Int, _ shortcuts: Shortcuts) -> String? {
        guard index != active else { return nil }
        if index == (active + 1) % count { return shortcuts.nextProfile }
        if index == (active - 1 + count) % count { return shortcuts.previousProfile }
        return nil
    }
}
