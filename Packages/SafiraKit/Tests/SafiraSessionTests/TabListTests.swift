// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

/// Opens one Tab per address, in order, and returns their identifiers.
@MainActor
private func openTabs(_ fixture: SessionFixture, _ addresses: [String]) -> [TabID] {
    addresses.map { address in
        fixture.session.openCommandBar(for: .newTab)
        fixture.session.submitCommandBar(address)
        return fixture.session.selectedTabID!
    }
}

@MainActor
@Suite struct ReorderTests {
    @Test func movingATabDownPutsItAtTheGivenPlace() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com", "d.com"])

        fixture.session.move(ids[0], to: 2)

        #expect(fixture.addresses == ["https://b.com", "https://c.com", "https://a.com", "https://d.com"])
    }

    @Test func movingATabUpPutsItAtTheGivenPlace() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com", "d.com"])

        fixture.session.move(ids[3], to: 1)

        #expect(fixture.addresses == ["https://a.com", "https://d.com", "https://b.com", "https://c.com"])
    }

    @Test func aPlacePastTheEndsIsClamped() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])

        fixture.session.move(ids[0], to: 99)
        fixture.session.move(ids[2], to: -5)

        #expect(fixture.addresses == ["https://c.com", "https://b.com", "https://a.com"])
    }

    @Test func movingByAnOffsetStopsAtTheEnds() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])

        fixture.session.move(ids[1], by: -1)

        #expect(fixture.addresses == ["https://b.com", "https://a.com", "https://c.com"])

        fixture.session.move(ids[1], by: -1)

        #expect(fixture.addresses == ["https://b.com", "https://a.com", "https://c.com"])

        fixture.session.move(ids[1], by: 2)

        #expect(fixture.addresses == ["https://a.com", "https://c.com", "https://b.com"])
    }

    @Test func movingKeepsTheSelectionAndLoadsNothing() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        fixture.session.select(ids[1])

        fixture.session.move(ids[1], to: 0)

        #expect(fixture.session.selectedTabID == ids[1])
        #expect(fixture.pages.values.map(\.loadCount) == [1, 1, 1])
    }

    @Test func movingATabOfAnotherSessionChangesNothing() {
        let fixture = SessionFixture()
        _ = openTabs(fixture, ["a.com", "b.com"])

        fixture.session.move(TabID(), to: 0)

        #expect(fixture.addresses == ["https://a.com", "https://b.com"])
    }
}

@MainActor
@Suite struct SelectionTests {
    @Test func selectingATabShowsItWithoutLoadingIt() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com"])

        fixture.session.select(ids[0])

        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://a.com")
        #expect(fixture.selectedPage?.loadCount == 1)
    }

    @Test func nextAndPreviousWrapAroundTheList() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])

        fixture.session.selectTab(offset: 1)

        #expect(fixture.session.selectedTabID == ids[0])

        fixture.session.selectTab(offset: -1)

        #expect(fixture.session.selectedTabID == ids[2])

        fixture.session.selectTab(offset: -1)

        #expect(fixture.session.selectedTabID == ids[1])
    }

    @Test func nextWithNoTabDoesNothing() {
        let fixture = SessionFixture()

        fixture.session.selectTab(offset: 1)

        #expect(fixture.session.selectedTabID == nil)
    }
}

@MainActor
@Suite struct ReopenClosedTabTests {
    @Test func reopeningBringsBackTheLastClosedTabAtItsPlaceAndSelectsIt() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        fixture.session.close(ids[1])

        let reopened = fixture.session.reopenClosedTab()

        #expect(fixture.addresses == ["https://a.com", "https://b.com", "https://c.com"])
        #expect(fixture.session.selectedTabID == reopened)
        #expect(fixture.selectedPage?.loadCount == 1)
        #expect(fixture.session.canReopenClosedTab == false)
    }

    @Test func closedTabsReopenLastClosedFirst() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        fixture.session.close(ids[0])
        fixture.session.close(ids[2])

        fixture.session.reopenClosedTab()

        #expect(fixture.addresses == ["https://b.com", "https://c.com"])

        fixture.session.reopenClosedTab()

        #expect(fixture.addresses == ["https://a.com", "https://b.com", "https://c.com"])
    }

    @Test func aTabReopensAtTheEndWhenItsPlaceNoLongerExists() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        fixture.session.close(ids[2])
        fixture.session.close(ids[1])
        fixture.session.close(ids[0])
        fixture.session.reopenClosedTab()
        fixture.session.reopenClosedTab()

        fixture.session.reopenClosedTab()

        #expect(fixture.addresses == ["https://a.com", "https://b.com", "https://c.com"])
    }

    @Test func aTabReopensAtItsLastAddress() throws {
        let fixture = SessionFixture()
        _ = openTabs(fixture, ["example.com"])
        try fixture.selectedPage?.followLink(to: #require(URL(string: "https://example.com/about")))
        fixture.session.closeSelectedTab()

        fixture.session.reopenClosedTab()

        #expect(fixture.addresses == ["https://example.com/about"])
    }

    @Test func aClosedTabIsDiscardedAndReopensWithANewPage() {
        let fixture = SessionFixture()
        _ = openTabs(fixture, ["example.com"])
        let closedPage = fixture.selectedPage
        fixture.session.closeSelectedTab()

        fixture.session.reopenClosedTab()

        #expect(closedPage?.isClosed == true)
        #expect(fixture.selectedPage !== closedPage)
        #expect(fixture.createdPageCount == 2)
    }

    @Test func anEmptyTabIsNotKeptForReopening() {
        let fixture = SessionFixture()
        fixture.session.openNewTab()
        fixture.session.closeSelectedTab()

        #expect(fixture.session.canReopenClosedTab == false)
        #expect(fixture.session.reopenClosedTab() == nil)
        #expect(fixture.session.tabs.isEmpty)
    }

    @Test func aNewSessionHasNothingToReopen() {
        let first = SessionFixture()
        _ = openTabs(first, ["example.com"])
        first.session.closeSelectedTab()

        let relaunched = SessionFixture()

        #expect(relaunched.session.canReopenClosedTab == false)
    }
}

@MainActor
@Suite struct NewTabCommandBarTests {
    @Test func newTabOpensTheCommandBarAndCreatesNoTabYet() {
        let fixture = SessionFixture()
        _ = openTabs(fixture, ["example.com"])

        fixture.session.openCommandBar(for: .newTab)

        #expect(fixture.session.commandBarTarget == .newTab)
        #expect(fixture.session.tabs.count == 1)
    }

    @Test func enterAfterNewTabOpensTheAddressInANewSelectedTab() {
        let fixture = SessionFixture()
        let first = openTabs(fixture, ["example.com"])[0]

        fixture.session.openCommandBar(for: .newTab)
        fixture.session.submitCommandBar("example.org")

        #expect(fixture.addresses == ["https://example.com", "https://example.org"])
        #expect(fixture.session.selectedTabID != first)
        #expect(fixture.session.commandBarTarget == nil)
    }

    @Test func escapeAfterNewTabCreatesNoTab() {
        let fixture = SessionFixture()
        let first = openTabs(fixture, ["example.com"])[0]

        fixture.session.openCommandBar(for: .newTab)
        fixture.session.dismissCommandBar()

        #expect(fixture.session.tabs.map(\.id) == [first])
        #expect(fixture.session.selectedTabID == first)
        #expect(fixture.session.commandBarTarget == nil)
        #expect(fixture.createdPageCount == 1)
    }

    @Test func blankTextAfterNewTabKeepsTheCommandBarOpenAndCreatesNoTab() {
        let fixture = SessionFixture()

        fixture.session.openCommandBar(for: .newTab)
        fixture.session.submitCommandBar("  ")

        #expect(fixture.session.tabs.isEmpty)
        #expect(fixture.session.commandBarTarget == .newTab)
    }

    @Test func theSelectedTabTargetReplacesThePageOfTheSelectedTab() {
        let fixture = SessionFixture()
        _ = openTabs(fixture, ["example.com"])

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.submitCommandBar("example.org")

        #expect(fixture.addresses == ["https://example.org"])
    }

    @Test func aSearchAfterNewTabWaitingForAnEngineStillOpensInANewTab() {
        let fixture = SessionFixture()
        _ = openTabs(fixture, ["example.com"])

        fixture.session.openCommandBar(for: .newTab)
        fixture.session.submitCommandBar("swift testing")

        #expect(fixture.session.tabs.count == 1)

        fixture.session.chooseSearchEngine(.duckDuckGo)

        #expect(fixture.addresses == ["https://example.com", "https://duckduckgo.com/?q=swift%20testing"])
    }
}

@MainActor
@Suite struct BackgroundTabTests {
    @Test func aCommandClickedLinkOpensABackgroundTabAtTheEnd() throws {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["example.com", "example.net"])
        fixture.session.select(ids[0])

        try fixture.selectedPage?.commandClickLink(to: #require(URL(string: "https://example.com/about")))

        #expect(fixture.addresses == ["https://example.com", "https://example.net", "https://example.com/about"])
        #expect(fixture.session.selectedTabID == ids[0])
        #expect(fixture.selectedPage?.loadCount == 1)
        #expect(fixture.createdPageCount == 3)
    }

    @Test func aTargetBlankLinkOpensABackgroundTabWithThePageTheEngineBuilt() throws {
        let fixture = SessionFixture()
        let opener = openTabs(fixture, ["example.com"])[0]

        let id = try fixture.clickTargetBlankLink(in: fixture.selectedPage,
                                                  to: #require(URL(string: "https://example.org")))

        #expect(fixture.session.tabs.map(\.id) == [opener, id])
        #expect(fixture.addresses == ["https://example.com", "https://example.org"])
        #expect(fixture.session.selectedTabID == opener)
        // The session neither built nor loaded that page: the engine did.
        #expect(fixture.createdPageCount == 1)
        #expect(fixture.pages[id]?.loadCount == 0)
    }

    @Test func aBackgroundTabIsAPlainTabThatClosesAndReopens() throws {
        let fixture = SessionFixture()
        _ = openTabs(fixture, ["example.com"])
        let id = try fixture.clickTargetBlankLink(in: fixture.selectedPage,
                                                  to: #require(URL(string: "https://example.org")))
        let page = fixture.pages[id]

        fixture.session.close(id)
        fixture.session.reopenClosedTab()

        #expect(page?.isClosed == true)
        #expect(fixture.addresses == ["https://example.com", "https://example.org"])
    }

    @Test func aClosedTabNoLongerOpensTabs() throws {
        let fixture = SessionFixture()
        _ = openTabs(fixture, ["example.com", "example.org"])
        let page = fixture.selectedPage
        fixture.session.closeSelectedTab()

        try page?.commandClickLink(to: #require(URL(string: "https://example.net")))

        #expect(fixture.addresses == ["https://example.com"])
    }
}

@MainActor
@Suite struct TabStateTests {
    @Test func aTabMirrorsItsPageMediaPlayback() {
        let fixture = SessionFixture()
        _ = openTabs(fixture, ["example.com"])

        fixture.selectedPage?.setPlayingMedia(true)

        #expect(fixture.session.selectedTab?.state.isPlayingMedia == true)

        fixture.selectedPage?.setPlayingMedia(false)

        #expect(fixture.session.selectedTab?.state.isPlayingMedia == false)
    }
}
