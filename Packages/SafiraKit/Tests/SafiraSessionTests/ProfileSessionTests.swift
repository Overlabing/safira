// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

@MainActor
@Suite struct CommandBarTests {
    @Test func anAddressOpensInANewTabWhenNoneIsOpen() {
        let fixture = SessionFixture()

        fixture.session.submitCommandBar("example.com")

        #expect(fixture.addresses == ["https://example.com"])
        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://example.com")
        #expect(fixture.selectedPage?.loadCount == 1)
    }

    @Test func anAddressReplacesThePageOfTheSelectedTab() {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")

        fixture.session.submitCommandBar("swift.org/documentation")

        #expect(fixture.addresses == ["https://swift.org/documentation"])
        #expect(fixture.session.selectedTab?.state.canGoBack == true)
    }

    @Test func blankTextOpensNothing() {
        let fixture = SessionFixture()

        fixture.session.submitCommandBar("   ")

        #expect(fixture.session.tabs.isEmpty)
    }

    @Test func aSearchUsesTheProfileSearchEngine() {
        let fixture = SessionFixture(searchEngine: .kagi)

        fixture.session.submitCommandBar("swift testing")

        #expect(fixture.addresses == ["https://kagi.com/search?q=swift%20testing"])
        #expect(fixture.session.searchAwaitingEngine == nil)
    }

    @Test func theFirstSearchWithoutAnEngineWaitsForTheUserToPickOne() {
        let fixture = SessionFixture()

        fixture.session.submitCommandBar("swift testing")

        #expect(fixture.session.searchAwaitingEngine == "swift testing")
        #expect(fixture.createdPageCount == 0)

        fixture.session.chooseSearchEngine(.duckDuckGo)

        #expect(fixture.session.searchAwaitingEngine == nil)
        #expect(fixture.session.profile.searchEngine == .duckDuckGo)
        #expect(fixture.addresses == ["https://duckduckgo.com/?q=swift%20testing"])
    }

    @Test func theChosenEngineIsKeptForTheNextSearches() {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("first")
        fixture.session.chooseSearchEngine(.ecosia)

        fixture.session.submitCommandBar("second")

        #expect(fixture.session.searchAwaitingEngine == nil)
        #expect(fixture.addresses == ["https://www.ecosia.org/search?q=second"])
    }

    @Test func cancellingTheEngineChoiceDropsTheSearchAndPicksNothing() {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("swift testing")

        fixture.session.cancelSearchEngineChoice()

        #expect(fixture.session.searchAwaitingEngine == nil)
        #expect(fixture.session.profile.searchEngine == nil)
        #expect(fixture.session.tabs.isEmpty)
    }
}

@MainActor
@Suite struct NavigationTests {
    @Test func backAndForwardMoveThroughTheTabHistory() {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")
        fixture.session.submitCommandBar("example.org")

        fixture.session.goBack()

        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://example.com")
        #expect(fixture.session.selectedTab?.state.canGoBack == false)
        #expect(fixture.session.selectedTab?.state.canGoForward == true)

        fixture.session.goForward()

        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://example.org")
        #expect(fixture.session.selectedTab?.state.canGoForward == false)
        #expect(fixture.selectedPage?.loadCount == 2)
    }

    @Test func backAndForwardDoNothingAtTheEndsOfTheHistory() {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")

        fixture.session.goBack()
        fixture.session.goForward()

        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://example.com")
    }

    @Test func aLinkClickedInThePageUpdatesTheTab() throws {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")

        try fixture.selectedPage?.followLink(to: #require(URL(string: "https://example.com/about")))

        #expect(fixture.addresses == ["https://example.com/about"])
        #expect(fixture.session.selectedTab?.state.canGoBack == true)
    }

    @Test func reloadReloadsTheSelectedPageOnly() {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")
        let first = fixture.selectedPage
        fixture.session.openNewTab()
        fixture.session.submitCommandBar("example.org")

        fixture.session.reload()

        #expect(fixture.selectedPage?.reloadCount == 1)
        #expect(first?.reloadCount == 0)
        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://example.org")
    }

    @Test func navigatingWithNoTabDoesNothing() {
        let fixture = SessionFixture()

        fixture.session.goBack()
        fixture.session.goForward()
        fixture.session.reload()

        #expect(fixture.createdPageCount == 0)
    }
}

@MainActor
@Suite struct TabTests {
    @Test func aNewTabIsSelectedAndEmptyAndCreatesNoPage() {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")

        let id = fixture.session.openNewTab()

        #expect(fixture.session.selectedTabID == id)
        #expect(fixture.addresses == ["https://example.com", nil])
        #expect(fixture.createdPageCount == 1)
    }

    @Test func anAddressTypedInANewTabLeavesTheOtherTabAlone() {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")
        fixture.session.openNewTab()

        fixture.session.submitCommandBar("example.org")

        #expect(fixture.addresses == ["https://example.com", "https://example.org"])
    }

    @Test func closingTheSelectedTabSelectsTheOneThatTakesItsPlace() {
        let fixture = SessionFixture()
        let first = fixture.session.openNewTab()
        let second = fixture.session.openNewTab()
        let third = fixture.session.openNewTab()
        fixture.session.select(second)

        fixture.session.closeSelectedTab()

        #expect(fixture.session.tabs.map(\.id) == [first, third])
        #expect(fixture.session.selectedTabID == third)
    }

    @Test func closingTheLastTabInTheListSelectsTheOneBefore() {
        let fixture = SessionFixture()
        let first = fixture.session.openNewTab()
        fixture.session.openNewTab()

        fixture.session.closeSelectedTab()

        #expect(fixture.session.selectedTabID == first)
    }

    @Test func closingATabThatIsNotSelectedKeepsTheSelection() {
        let fixture = SessionFixture()
        let first = fixture.session.openNewTab()
        let second = fixture.session.openNewTab()

        fixture.session.close(first)

        #expect(fixture.session.tabs.map(\.id) == [second])
        #expect(fixture.session.selectedTabID == second)
    }

    @Test func closingATabClosesItsPage() {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")
        let page = fixture.selectedPage

        fixture.session.closeSelectedTab()

        #expect(page?.isClosed == true)
    }

    @Test func closingTheOnlyTabLeavesNoTabAndTheNextAddressOpensANewOne() {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")

        fixture.session.closeSelectedTab()

        #expect(fixture.session.tabs.isEmpty)
        #expect(fixture.session.selectedTabID == nil)

        fixture.session.submitCommandBar("example.org")

        #expect(fixture.addresses == ["https://example.org"])
    }

    @Test func selectingATabOfAnotherSessionIsIgnored() {
        let fixture = SessionFixture()
        let mine = fixture.session.openNewTab()

        fixture.session.select(TabID())

        #expect(fixture.session.selectedTabID == mine)
    }

    @Test func swappingBetweenTwentyTabsNeverLoadsOrReloadsAPage() {
        let fixture = SessionFixture()
        var ids: [TabID] = []
        for number in 1...20 {
            ids.append(fixture.session.openNewTab())
            fixture.session.submitCommandBar("example.com/\(number)")
        }

        for _ in 1...3 {
            for id in ids.shuffled() + ids.reversed() {
                fixture.session.select(id)
            }
        }

        #expect(fixture.createdPageCount == 20)
        #expect(fixture.pages.values.map(\.loadCount) == Array(repeating: 1, count: 20))
        #expect(fixture.pages.values.map(\.reloadCount) == Array(repeating: 0, count: 20))
        #expect(fixture.addresses.compactMap { $0 } == (1...20).map { "https://example.com/\($0)" })
    }
}
