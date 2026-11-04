// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// What is saved of one Tab so that it comes back after a relaunch.
public struct TabRecord: Hashable, Sendable {
    public let id: TabID
    /// The last address, which a Tab falls back to when its navigation state cannot be restored.
    public var address: URL?
    public var title: String?
    /// The web engine's opaque navigation state (back-forward list, scroll, form fields); nil when the Tab is saved by
    /// its address only.
    public var navigationState: Data?
    /// The macOS build that wrote `navigationState`; its format is only trusted on the same build.
    public var navigationStateOSBuild: String?
    /// The address a Pinned tab was pinned at; nil for a Tab that is not pinned, or pinned while blank.
    public var pinnedAddress: URL?

    public init(id: TabID, address: URL? = nil, title: String? = nil, navigationState: Data? = nil,
                navigationStateOSBuild: String? = nil, pinnedAddress: URL? = nil) {
        self.id = id
        self.address = address
        self.title = title
        self.navigationState = navigationState
        self.navigationStateOSBuild = navigationStateOSBuild
        self.pinnedAddress = pinnedAddress
    }
}

/// What is saved of a Folder: its own fields and what it holds, in order.
public struct FolderRecord: Hashable, Sendable {
    public let id: FolderID
    public var name: String
    public var isExpanded: Bool
    public var items: [PinnedItemRecord]

    public init(id: FolderID, name: String, isExpanded: Bool = true, items: [PinnedItemRecord] = []) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
        self.items = items
    }
}

/// An entry of a pinned area or of a Folder. A plain Tab has no such form, so a Folder cannot hold one.
public enum PinnedItemRecord: Hashable, Sendable {
    case tab(TabRecord)
    case folder(FolderRecord)
}

/// What is saved of one Space: its own fields, its pinned area and its other Tabs, in sidebar order.
public struct SpaceRecord: Hashable, Sendable {
    public let id: SpaceID
    public var name: String
    public var emoji: String
    /// The Space's Theme, picked from a Palette; nil until Themes exist.
    public var paletteID: String?
    /// The pinned area: Pinned tabs and Folders, in order.
    public var pinned: [PinnedItemRecord]
    /// The Tabs that are not pinned, in order.
    public var tabs: [TabRecord]
    public var selectedTabID: TabID?

    public init(id: SpaceID, name: String, emoji: String, paletteID: String? = nil, pinned: [PinnedItemRecord] = [],
                tabs: [TabRecord] = [], selectedTabID: TabID? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.paletteID = paletteID
        self.pinned = pinned
        self.tabs = tabs
        self.selectedTabID = selectedTabID
    }
}

/// The saved Spaces of a Profile, in sidebar order, and the one that was active.
public struct SavedSession: Hashable, Sendable {
    public var spaces: [SpaceRecord]
    public var activeSpaceID: SpaceID?

    public init(spaces: [SpaceRecord] = [], activeSpaceID: SpaceID? = nil) {
        self.spaces = spaces
        self.activeSpaceID = activeSpaceID
    }

    /// The active Space, or the first one when none is named.
    public var activeSpace: SpaceRecord? {
        spaces.first { $0.id == activeSpaceID } ?? spaces.first
    }
}

extension [PinnedItemRecord] {
    /// Every Pinned tab, depth first, in the order the pinned area shows them.
    public var pinnedTabs: [TabRecord] {
        flatMap { item -> [TabRecord] in
            switch item {
            case .tab(let tab): [tab]
            case .folder(let folder): folder.items.pinnedTabs
            }
        }
    }
}

extension SpaceRecord {
    /// Every Tab of the Space: the Pinned tabs, then the others.
    public var allTabs: [TabRecord] {
        pinned.pinnedTabs + tabs
    }
}
