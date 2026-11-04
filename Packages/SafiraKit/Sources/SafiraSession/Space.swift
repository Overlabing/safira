// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Observation
import SafiraCore

/// A named group of Tabs inside one Profile. Its Tabs use the Profile's pages, so every Space of a Profile shares its
/// logins. Only its `ProfileSession` changes it.
@MainActor
@Observable
public final class Space: Identifiable {
    public let id: SpaceID
    public internal(set) var name: String
    public internal(set) var emoji: String
    /// The Space's Theme, picked from a Palette; nil until Themes exist.
    public internal(set) var paletteID: String?
    /// The Space's Tabs, in sidebar order.
    public internal(set) var tabs: [Tab] = []
    /// The Tab shown when the Space is active.
    public internal(set) var selectedTabID: TabID?

    init(id: SpaceID, name: String, emoji: String, paletteID: String? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.paletteID = paletteID
    }

    public var selectedTab: Tab? {
        tabs.first { $0.id == selectedTabID }
    }

    var record: SpaceRecord {
        SpaceRecord(id: id, name: name, emoji: emoji, paletteID: paletteID, tabs: tabs.map(\.record),
                    selectedTabID: selectedTabID)
    }
}
