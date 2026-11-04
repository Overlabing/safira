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

    public init(id: TabID, address: URL? = nil, title: String? = nil, navigationState: Data? = nil,
                navigationStateOSBuild: String? = nil) {
        self.id = id
        self.address = address
        self.title = title
        self.navigationState = navigationState
        self.navigationStateOSBuild = navigationStateOSBuild
    }
}

/// What is saved of one Space: its own fields and its Tabs, in sidebar order.
public struct SpaceRecord: Hashable, Sendable {
    public let id: SpaceID
    public var name: String
    public var emoji: String
    /// The Space's Theme, picked from a Palette; nil until Themes exist.
    public var paletteID: String?
    public var tabs: [TabRecord]
    public var selectedTabID: TabID?

    public init(id: SpaceID, name: String, emoji: String, paletteID: String? = nil, tabs: [TabRecord] = [],
                selectedTabID: TabID? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.paletteID = paletteID
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
