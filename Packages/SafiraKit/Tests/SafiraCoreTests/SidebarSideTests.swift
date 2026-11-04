// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

@Suite struct SidebarSideTests {
    private func emptyDefaults() -> UserDefaults {
        let name = "SidebarSideTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theSidebarStartsOnTheLeft() {
        #expect(SidebarSideStore(defaults: emptyDefaults()).load() == .left)
    }

    @Test func theChosenSideIsKeptAcrossLaunches() {
        let defaults = emptyDefaults()
        SidebarSideStore(defaults: defaults).save(.right)

        #expect(SidebarSideStore(defaults: defaults).load() == .right)
        #expect(defaults.string(forKey: "window.sidebarSide") == "right")
    }

    @Test func aDamagedValueKeepsTheSidebarOnTheLeft() {
        let defaults = emptyDefaults()
        defaults.set("middle", forKey: "window.sidebarSide")

        #expect(SidebarSideStore(defaults: defaults).load() == .left)
    }

    @Test func theDefaultIsListedAsASwitchThatStartsOff() throws {
        let entry = try #require(SidebarSide.defaultEntries.first)

        #expect(entry.id == "window.sidebarSide")
        #expect(entry.title == "Sidebar on the Right")
        #expect(entry.value == "Off, on the left")
        #expect(entry.control == .toggle(isOn: false))
        #expect(entry.isUserFacing)
    }
}
