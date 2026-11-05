// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Preferences
import SafiraCore
import Testing

@Suite struct SidebarSideTests {
    @Test func theSidebarStartsOnTheLeft() {
        #expect(SidebarSideStore(store: InMemoryKeyValueStore()).load(unreadable: { _ in }) == .left)
    }

    @Test func theChosenSideIsKeptAcrossLaunches() {
        let store = InMemoryKeyValueStore()
        SidebarSideStore(store: store).save(.right)

        #expect(SidebarSideStore(store: store).load(unreadable: { _ in }) == .right)
        #expect(store.data(forKey: "window.sidebarSide") == Data(#""right""#.utf8))
    }

    @Test func aDamagedValueKeepsTheSidebarOnTheLeftAndIsReportedOnce() {
        let store = InMemoryKeyValueStore()
        store.setData(Data(#""middle""#.utf8), forKey: "window.sidebarSide")
        var problems: [PreferenceError] = []

        #expect(SidebarSideStore(store: store).load { problems.append($0) } == .left)
        #expect(SidebarSideStore(store: store).load { problems.append($0) } == .left)
        #expect(problems == [.unreadable(key: "window.sidebarSide")])
    }

    @Test func theSideTheOldStoreKeptIsReadAfterTheMigration() throws {
        let (defaults, domain) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set("right", forKey: "window.sidebarSide")

        LegacyPreference.migrate([SidebarSideStore.legacy], in: defaults, domain: domain)

        #expect(SidebarSideStore(store: defaults).load(unreadable: { _ in }) == .right)
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
