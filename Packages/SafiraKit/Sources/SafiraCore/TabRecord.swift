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

/// The saved Tabs of a Profile, in sidebar order, and the one that was selected.
public struct SavedSession: Hashable, Sendable {
    public var tabs: [TabRecord]
    public var selectedTabID: TabID?

    public init(tabs: [TabRecord] = [], selectedTabID: TabID? = nil) {
        self.tabs = tabs
        self.selectedTabID = selectedTabID
    }
}
