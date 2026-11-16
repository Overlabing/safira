// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

/// ⌘L in a Pinned tab: an address or a search on the Pinned tab's own site loads in it, anything else opens in a new
/// Tab as after ⌘T, so that the Pinned tab stays on its site.
@MainActor
@Suite struct PinnedCommandBarTests {
    /// A Pinned tab at `address`, selected, with one plain Tab below the pinned area.
    private func pinnedTab(at address: String, searchEngine: SearchEngine? = nil)
        -> (fixture: SessionFixture, pinned: TabID, plain: TabID) {
        let fixture = SessionFixture(searchEngine: searchEngine)
        let plain = fixture.visit("https://plain.example/")
        let pinned = fixture.visit(address)
        fixture.session.pin(pinned)
        return (fixture, pinned, plain)
    }

    private func loads(_ fixture: SessionFixture, _ id: TabID) -> [String] {
        fixture.pages[id]?.loads.map(\.url.absoluteString) ?? []
    }

    @Test func anAddressOnAnotherSiteOpensInANewTabAsCommandTWould() throws {
        let (fixture, pinned, plain) = pinnedTab(at: "https://mail.example.com/inbox")

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.submitCommandBar("other.org/page")

        let new = try #require(fixture.session.selectedTabID)
        #expect(new != pinned)
        #expect(fixture.session.tabs.map(\.id) == [plain, new])
        #expect(fixture.addresses == ["https://plain.example/", "https://other.org/page"])
        #expect(loads(fixture, pinned) == ["https://mail.example.com/inbox"])
        #expect(fixture.session.activeSpace.pinnedTabs.map(\.id) == [pinned])
    }

    @Test func anAddressOnASubdomainOfTheSameSiteLoadsInThePinnedTab() {
        let (fixture, pinned, plain) = pinnedTab(at: "https://mail.google.com/mail")

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.submitCommandBar("https://google.com/calendar")

        #expect(fixture.session.selectedTabID == pinned)
        #expect(fixture.session.tabs.map(\.id) == [plain])
        #expect(loads(fixture, pinned) == ["https://mail.google.com/mail", "https://google.com/calendar"])
    }

    @Test func twoSitesOfTheSameHostingServiceAreDifferentSites() {
        let (fixture, pinned, _) = pinnedTab(at: "https://foo.github.io/")

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.submitCommandBar("https://bar.github.io/")

        #expect(fixture.session.selectedTabID != pinned)
        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://bar.github.io/")
        #expect(loads(fixture, pinned) == ["https://foo.github.io/"])
    }

    @Test func theSiteComparedIsThePinnedAddressNotWhereTheTabWentSince() {
        let (fixture, pinned, _) = pinnedTab(at: "https://a.example/home")
        fixture.pages[pinned]?.followLink(to: URL(string: "https://b.example/elsewhere")!)

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.submitCommandBar("https://b.example/more")
        #expect(fixture.session.selectedTabID != pinned)

        fixture.session.select(pinned)
        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.submitCommandBar("https://www.a.example/back")
        #expect(fixture.session.selectedTabID == pinned)
        #expect(fixture.pages[pinned]?.state.url?.absoluteString == "https://www.a.example/back")
    }

    @Test func aSearchOpensInANewTab() throws {
        let (fixture, pinned, plain) = pinnedTab(at: "https://mail.example.com/", searchEngine: .kagi)

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.submitCommandBar("swift testing")

        let new = try #require(fixture.session.selectedTabID)
        #expect(new != pinned)
        #expect(fixture.session.tabs.map(\.id) == [plain, new])
        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://kagi.com/search?q=swift%20testing")
        #expect(loads(fixture, pinned) == ["https://mail.example.com/"])
    }

    @Test func aSearchOnTheSearchEnginesOwnSiteLoadsInThePinnedTab() {
        let (fixture, pinned, plain) = pinnedTab(at: "https://google.com/", searchEngine: .google)

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.submitCommandBar("swift testing")

        #expect(fixture.session.selectedTabID == pinned)
        #expect(fixture.session.tabs.map(\.id) == [plain])
        #expect(fixture.pages[pinned]?.state.url?.absoluteString == "https://www.google.com/search?q=swift%20testing")
    }

    @Test func aSearchWaitingForASearchEngineStillOpensInANewTab() {
        let (fixture, pinned, _) = pinnedTab(at: "https://mail.example.com/")

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.submitCommandBar("swift testing")
        fixture.session.chooseSearchEngine(.duckDuckGo)

        #expect(fixture.session.selectedTabID != pinned)
        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://duckduckgo.com/?q=swift%20testing")
        #expect(loads(fixture, pinned) == ["https://mail.example.com/"])
    }

    @Test func aHistorySuggestionOnAnotherSiteOpensInANewTabAndOneOnTheSameSiteInPlace() {
        let (fixture, pinned, plain) = pinnedTab(at: "https://mail.example.com/")
        let elsewhere = URL(string: "https://other.org/post")!
        let sameSite = URL(string: "https://docs.example.com/guide")!

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.openSuggestion(CommandBarSuggestion(kind: .history(elsewhere), title: "Post", address: elsewhere))
        #expect(fixture.session.selectedTabID != pinned)
        #expect(fixture.session.tabs.count == 2)

        fixture.session.select(pinned)
        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.openSuggestion(CommandBarSuggestion(kind: .history(sameSite), title: "Guide", address: sameSite))
        #expect(fixture.session.selectedTabID == pinned)
        #expect(fixture.session.tabs.count == 2)
        #expect(fixture.session.tabs.first?.id == plain)
        #expect(loads(fixture, pinned) == ["https://mail.example.com/", "https://docs.example.com/guide"])
    }

    @Test func switchToTabStillShowsTheOpenTab() {
        let (fixture, pinned, plain) = pinnedTab(at: "https://mail.example.com/")
        let address = URL(string: "https://plain.example/")!

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.openSuggestion(CommandBarSuggestion(kind: .openTab(plain), title: "Plain", address: address))

        #expect(fixture.session.selectedTabID == plain)
        #expect(fixture.session.tabs.map(\.id) == [plain])
        #expect(loads(fixture, pinned) == ["https://mail.example.com/"])
    }

    @Test func anUnpinnedTabLoadsAnySiteInPlace() {
        let fixture = SessionFixture()
        let tab = fixture.visit("https://mail.example.com/")

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.submitCommandBar("https://other.org/")

        #expect(fixture.session.selectedTabID == tab)
        #expect(fixture.session.tabs.map(\.id) == [tab])
        #expect(fixture.addresses == ["https://other.org/"])
    }

    @Test func commandTFromAPinnedTabStillOpensANewTabForTheSameSite() {
        let (fixture, pinned, plain) = pinnedTab(at: "https://mail.example.com/")

        fixture.session.openCommandBar(for: .newTab)
        fixture.session.submitCommandBar("https://mail.example.com/sent")

        #expect(fixture.session.selectedTabID != pinned)
        #expect(fixture.session.tabs.count == 2)
        #expect(fixture.session.tabs.first?.id == plain)
        #expect(loads(fixture, pinned) == ["https://mail.example.com/"])
    }

    @Test func aTabPinnedBlankLoadsAnySiteInPlace() {
        let fixture = SessionFixture()
        let blank = fixture.session.openNewTab()
        fixture.session.pin(blank)

        fixture.session.openCommandBar(for: .selectedTab)
        fixture.session.submitCommandBar("https://other.org/")

        #expect(fixture.session.selectedTabID == blank)
        #expect(fixture.session.tabs.isEmpty)
        #expect(loads(fixture, blank) == ["https://other.org/"])
    }
}
