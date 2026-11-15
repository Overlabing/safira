// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

/// #121: a page whose content process ended reloads once by itself when it is shown; a second crash shows the
/// crashed state, whose Reload is the user's.
@MainActor
@Suite struct CrashedPageTests {
    @Test func theShownTabReloadsOnceAfterACrash() throws {
        let fixture = SessionFixture()
        fixture.visit("https://mail.example/inbox")
        let page = try #require(fixture.selectedPage)

        page.crash()
        #expect(fixture.session.selectedTab?.crash == .reloadWhenShown)
        fixture.session.selectedTabIsShown()

        #expect(page.reloadCount == 1)
        #expect(fixture.session.selectedTab?.crash == .reloaded)
        fixture.session.selectedTabIsShown()
        #expect(page.reloadCount == 1)
    }

    @Test func aSecondCrashShowsTheCrashedStateAndDoesNotReload() throws {
        let fixture = SessionFixture()
        fixture.visit("https://mail.example/inbox")
        let page = try #require(fixture.selectedPage)
        page.crash()
        fixture.session.selectedTabIsShown()

        page.crash()
        fixture.session.selectedTabIsShown()

        #expect(fixture.session.selectedTab?.crash == .crashed)
        #expect(page.reloadCount == 1)
    }

    @Test func reloadFromTheCrashedStateReloadsAndAThirdCrashShowsItAgain() throws {
        let fixture = SessionFixture()
        fixture.visit("https://mail.example/inbox")
        let page = try #require(fixture.selectedPage)
        page.crash()
        fixture.session.selectedTabIsShown()
        page.crash()

        fixture.session.reload()
        #expect(page.reloadCount == 2)
        #expect(fixture.session.selectedTab?.crash == .reloaded)

        page.crash()
        fixture.session.selectedTabIsShown()
        #expect(fixture.session.selectedTab?.crash == .crashed)
        #expect(page.reloadCount == 2)
    }

    @Test func aHiddenTabReloadsOnlyWhenItIsNextShown() throws {
        let fixture = SessionFixture()
        let hidden = fixture.visit("https://mail.example/inbox")
        let hiddenPage = try #require(fixture.pages[hidden])
        fixture.visit("https://news.example/today")
        fixture.session.selectedTabIsShown()

        hiddenPage.crash()
        fixture.session.selectedTabIsShown()
        #expect(hiddenPage.reloadCount == 0)

        fixture.session.select(hidden)
        fixture.session.selectedTabIsShown()
        #expect(hiddenPage.reloadCount == 1)
        #expect(fixture.session.selectedTab?.crash == .reloaded)
    }

    @Test func leavingTheAddressGivesThePageANewAutomaticReload() throws {
        let fixture = SessionFixture()
        fixture.visit("https://mail.example/inbox")
        let page = try #require(fixture.selectedPage)
        page.crash()
        fixture.session.selectedTabIsShown()

        page.followLink(to: URL(string: "https://mail.example/sent")!)
        #expect(fixture.session.selectedTab?.crash == PageCrash.none)

        page.crash()
        fixture.session.selectedTabIsShown()
        #expect(page.reloadCount == 2)
        #expect(fixture.session.selectedTab?.crash == .reloaded)
    }

    @Test func typingAnAddressInACrashedTabClearsTheCrashedState() throws {
        let fixture = SessionFixture()
        fixture.visit("https://mail.example/inbox")
        let page = try #require(fixture.selectedPage)
        page.crash()
        fixture.session.selectedTabIsShown()
        page.crash()

        fixture.session.submitCommandBar("https://news.example/today")

        #expect(fixture.session.selectedTab?.crash == PageCrash.none)
        #expect(page.loads.last?.url.absoluteString == "https://news.example/today")
    }
}
