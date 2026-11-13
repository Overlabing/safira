// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

@Suite struct RetiredPreferencesTests {
    /// The sidebar is always on the left: a side saved by an earlier version, plain text or JSON, is removed at launch.
    @Test(arguments: ["right", #""right""#])
    func aSavedSidebarSideIsRemoved(saved: String) throws {
        let (defaults, domain) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(saved, forKey: "window.sidebarSide")
        defaults.set(true, forKey: "window.compactMode")

        RetiredPreferences.remove(from: defaults)

        #expect(defaults.object(forKey: "window.sidebarSide") == nil)
        #expect(defaults.bool(forKey: "window.compactMode") == true)
    }
}
