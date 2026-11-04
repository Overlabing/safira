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
    /// The id of the Space's Theme, picked from the Palette; nil for a Space made before Themes existed, which then wears
    /// its Profile's.
    public internal(set) var paletteID: String?
    /// The pinned area above the other Tabs: Pinned tabs and Folders, in order. It belongs to this Space alone.
    public internal(set) var pinned: [PinnedItem] = []
    /// The Space's Tabs that are not pinned, in sidebar order.
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
        allTabs.first { $0.id == selectedTabID }
    }

    /// Every Pinned tab, depth first, in the order the pinned area shows them.
    public var pinnedTabs: [Tab] {
        pinned.pinnedTabs
    }

    /// Every Folder of the pinned area, depth first.
    public var folders: [Folder] {
        pinned.folders
    }

    /// Every Tab in sidebar order: the Pinned tabs, then the others.
    public var allTabs: [Tab] {
        pinnedTabs + tabs
    }

    /// The Tabs the sidebar shows, in order: the Pinned tabs a collapsed Folder does not hide, then the others.
    public var visibleTabs: [Tab] {
        pinned.visiblePinnedTabs + tabs
    }

    public func folder(_ id: FolderID) -> Folder? {
        folders.first { $0.id == id }
    }

    /// The Folder that holds a pinned item, nil for the top of the pinned area; also nil when it is not in the Space.
    func container(of item: PinnedItemID) -> Folder? {
        folders.first { folder in folder.items.contains { $0.id == item } }
    }

    /// Takes a Pinned tab or a Folder out of wherever it sits in the pinned area.
    func remove(_ item: PinnedItemID) -> PinnedItem? {
        let owner = container(of: item)?.id
        guard var items = items(in: owner), let index = items.firstIndex(where: { $0.id == item }) else { return nil }
        let removed = items.remove(at: index)
        setItems(items, in: owner)
        return removed
    }

    func holds(_ item: PinnedItemID) -> Bool {
        switch item {
        case .tab(let id): pinnedTabs.contains { $0.id == id }
        case .folder(let id): folder(id) != nil
        }
    }

    /// The items of the top of the pinned area or of one Folder.
    func items(in folder: FolderID?) -> [PinnedItem]? {
        guard let folder else { return pinned }
        return self.folder(folder)?.items
    }

    func setItems(_ items: [PinnedItem], in folder: FolderID?) {
        if let folder {
            self.folder(folder)?.items = items
        } else {
            pinned = items
        }
    }

    var record: SpaceRecord {
        SpaceRecord(id: id, name: name, emoji: emoji, paletteID: paletteID, pinned: pinned.map(\.record),
                    tabs: tabs.map(\.record), selectedTabID: selectedTabID)
    }
}
