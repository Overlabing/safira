// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// The saved session of a Profile with a single Space, for tests about Tabs alone.
extension SavedSession {
    static let onlySpace = SpaceID(rawValue: UUID(uuidString: "5A5A5A5A-0000-4000-8000-000000000001")!)

    init(tabs: [TabRecord], selectedTabID: TabID? = nil) {
        self.init(spaces: [SpaceRecord(id: Self.onlySpace, name: "Home", emoji: "🏠", tabs: tabs,
                                       selectedTabID: selectedTabID)],
                  activeSpaceID: Self.onlySpace)
    }

    /// The Tabs of the active Space.
    var tabs: [TabRecord] {
        activeSpace?.tabs ?? []
    }

    var selectedTabID: TabID? {
        activeSpace?.selectedTabID
    }
}
