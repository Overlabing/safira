// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import Testing

@MainActor
private func openTab(_ fixture: SessionFixture, _ address: String) -> TabID {
    fixture.session.openCommandBar(for: .newTab)
    fixture.session.submitCommandBar(address)
    return fixture.session.selectedTabID!
}

@MainActor
private func pinnedTab(_ fixture: SessionFixture, _ id: TabID) throws -> SafiraSession.Tab {
    try #require(fixture.session.activeSpace.pinnedTabs.first { $0.id == id })
}

@MainActor
@Suite struct PinnedAddressTests {
    @Test func aPinnedTabIsAwayOnlyWhileItShowsAnotherPage() throws {
        let fixture = SessionFixture()
        let id = openTab(fixture, "https://a.com/home")
        fixture.session.pin(id)
        let tab = try pinnedTab(fixture, id)
        #expect(!tab.isAwayFromPinnedAddress)

        fixture.pages[id]?.followLink(to: URL(string: "https://a.com/other")!)
        #expect(tab.isAwayFromPinnedAddress)

        fixture.pages[id]?.followLink(to: URL(string: "HTTPS://A.COM/home/#top")!)
        #expect(!tab.isAwayFromPinnedAddress)
    }

    @Test func aPlainTabIsNeverAway() {
        let fixture = SessionFixture()
        let id = openTab(fixture, "https://a.com")
        fixture.pages[id]?.followLink(to: URL(string: "https://b.com")!)

        #expect(fixture.session.tabs[0].isAwayFromPinnedAddress == false)
        #expect(!fixture.session.returnToPinnedAddress(id))
        #expect(!fixture.session.replacePinnedAddress(id))
    }

    @Test func theIconOfAnAwayPinnedTabLoadsThePinnedAddressAndKeepsTheLeftPageInBack() throws {
        let fixture = SessionFixture()
        let pinned = openTab(fixture, "https://a.com/home")
        fixture.session.pin(pinned)
        fixture.pages[pinned]?.followLink(to: URL(string: "https://a.com/other")!)
        let other = openTab(fixture, "https://b.com")

        fixture.session.clickIcon(of: pinned)

        let page = try #require(fixture.pages[pinned])
        #expect(fixture.session.selectedTabID == pinned)
        #expect(page.loads.map(\.url.absoluteString) == ["https://a.com/home", "https://a.com/home"])
        #expect(page.state.url?.absoluteString == "https://a.com/home")
        #expect(page.state.canGoBack)
        #expect(try !pinnedTab(fixture, pinned).isAwayFromPinnedAddress)
        fixture.session.goBack()
        #expect(page.state.url?.absoluteString == "https://a.com/other")
        #expect(fixture.pages[other]?.loadCount == 1)
    }

    @Test func theIconOfAPinnedTabAtItsPinnedAddressOnlySelectsIt() throws {
        let fixture = SessionFixture()
        let pinned = openTab(fixture, "https://a.com/home")
        fixture.session.pin(pinned)
        fixture.pages[pinned]?.followLink(to: URL(string: "https://a.com/home/")!)
        _ = openTab(fixture, "https://b.com")

        fixture.session.clickIcon(of: pinned)

        #expect(fixture.session.selectedTabID == pinned)
        #expect(fixture.pages[pinned]?.loadCount == 1)
    }

    @Test func theIconOfAPlainTabOnlySelectsIt() {
        let fixture = SessionFixture()
        let first = openTab(fixture, "https://a.com")
        _ = openTab(fixture, "https://b.com")

        fixture.session.clickIcon(of: first)

        #expect(fixture.session.selectedTabID == first)
        #expect(fixture.pages[first]?.loadCount == 1)
    }

    @Test func goingBackFromTheMenuWorksInAnotherSpace() throws {
        let fixture = SessionFixture()
        let pinned = openTab(fixture, "https://a.com/home")
        fixture.session.pin(pinned)
        fixture.pages[pinned]?.followLink(to: URL(string: "https://a.com/other")!)
        let home = fixture.session.activeSpaceID
        try fixture.session.createSpace(name: "Reading")

        #expect(fixture.session.returnToPinnedAddress(pinned))

        #expect(fixture.session.activeSpaceID == home)
        #expect(fixture.session.selectedTabID == pinned)
        #expect(fixture.pages[pinned]?.state.url?.absoluteString == "https://a.com/home")
    }

    @Test func theSelectedTabCommandGoesBack() {
        let fixture = SessionFixture()
        let pinned = openTab(fixture, "https://a.com/home")
        fixture.session.pin(pinned)
        fixture.pages[pinned]?.followLink(to: URL(string: "https://a.com/other")!)

        fixture.session.returnSelectedTabToPinnedAddress()

        #expect(fixture.pages[pinned]?.state.url?.absoluteString == "https://a.com/home")
    }

    @Test func replacingThePinnedAddressTakesTheCurrentPage() throws {
        let fixture = SessionFixture()
        let pinned = openTab(fixture, "https://a.com/home")
        fixture.session.pin(pinned)
        #expect(!fixture.session.replacePinnedAddress(pinned))
        fixture.pages[pinned]?.followLink(to: URL(string: "https://a.com/inbox")!)

        #expect(fixture.session.replacePinnedAddress(pinned))

        let tab = try pinnedTab(fixture, pinned)
        #expect(tab.pinnedAddress?.absoluteString == "https://a.com/inbox")
        #expect(!tab.isAwayFromPinnedAddress)
        #expect(!fixture.session.returnToPinnedAddress(pinned))
    }

    @Test func aReplacedPinnedAddressSurvivesARelaunch() async throws {
        let disk = Disk()
        let before = SessionFixture()
        let pinned = openTab(before, "https://a.com/home")
        before.session.pin(pinned)
        before.pages[pinned]?.followLink(to: URL(string: "https://a.com/inbox")!)
        before.session.replacePinnedAddress(pinned)
        await SessionAutosave(session: before.session, database: try ProfileDatabase(file: disk.file)).saveNow()

        let after = SessionFixture()
        after.session.restore(try ProfileDatabase(file: disk.file).savedSession())

        let tab = try #require(after.session.activeSpace.pinnedTabs.first)
        #expect(tab.pinnedAddress?.absoluteString == "https://a.com/inbox")
        #expect(!tab.isAwayFromPinnedAddress)
    }

    @Test func aRestoredAwayPinnedTabWakesThenGoesBackWithItsHistory() async throws {
        let disk = Disk()
        let before = SessionFixture()
        let pinned = openTab(before, "https://a.com/home")
        before.session.pin(pinned)
        before.pages[pinned]?.followLink(to: URL(string: "https://a.com/other")!)
        _ = openTab(before, "https://b.com")
        await SessionAutosave(session: before.session, database: try ProfileDatabase(file: disk.file)).saveNow()

        let after = SessionFixture()
        after.session.restore(try ProfileDatabase(file: disk.file).savedSession())
        let tab = try #require(after.session.activeSpace.pinnedTabs.first)
        #expect(tab.isAwayFromPinnedAddress)

        after.session.clickIcon(of: pinned)

        let page = try #require(after.pages[pinned])
        #expect(page.restoreCount == 1)
        #expect(page.state.url?.absoluteString == "https://a.com/home")
        after.session.goBack()
        #expect(page.state.url?.absoluteString == "https://a.com/other")
    }
}
