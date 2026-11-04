// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

private func address(_ text: String) -> NormalizedAddress {
    NormalizedAddress(URL(string: text)!)!
}

@MainActor
@Suite struct MatchingTabTests {
    @Test func aTabWithTheSameNormalizedAddressMatches() {
        let fixture = SessionFixture()
        fixture.visit("https://Example.com/docs/")
        let other = fixture.visit("https://example.com/docs/api")
        fixture.visit("https://swift.org")

        let match = fixture.session.matchingTab(for: address("https://example.COM/docs/api?utm_source=mail&fbclid=1#top"))

        #expect(match == MatchingTab(profile: fixture.session.profileID, space: fixture.session.activeSpaceID, tab: other))
    }

    @Test func noTabMatchesAnAddressNobodyShows() {
        let fixture = SessionFixture()
        fixture.visit("https://example.com/docs")

        #expect(fixture.session.matchingTab(for: address("https://example.com/docs?page=2")) == nil)
        #expect(fixture.session.matchingTab(for: address("http://example.com/docs")) == nil)
    }

    @Test func aTabMatchesByItsCurrentAddressNotTheOneItOpenedWith() {
        let fixture = SessionFixture()
        let id = fixture.visit("https://example.com/start")
        fixture.pages[id]?.followLink(to: URL(string: "https://example.com/next")!)

        #expect(fixture.session.matchingTab(for: address("https://example.com/start")) == nil)
        #expect(fixture.session.matchingTab(for: address("https://example.com/next"))?.tab == id)
    }

    @Test func aTabOfAnotherSpaceMatchesAndFocusingItSwitchesSpace() {
        let fixture = SessionFixture()
        let home = fixture.session.activeSpaceID
        let id = fixture.visit("https://example.com/docs")
        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")
        fixture.visit("https://swift.org")

        let match = fixture.session.matchingTab(for: address("https://example.com/docs#intro"))
        #expect(match == MatchingTab(profile: fixture.session.profileID, space: home, tab: id))
        #expect(fixture.session.activeSpaceID == reading)

        #expect(fixture.session.focus(match!, openedFrom: URL(string: "https://example.com/docs#intro")!))

        #expect(fixture.session.activeSpaceID == home)
        #expect(fixture.session.selectedTabID == id)
        #expect(fixture.session.spaces.map(\.tabs.count) == [1, 1])
    }

    @Test func theActiveSpaceIsSearchedBeforeTheOthers() {
        let fixture = SessionFixture()
        fixture.visit("https://example.com/docs")
        fixture.session.createSpace(name: "Reading", emoji: "📚")
        let second = fixture.visit("https://example.com/docs")

        #expect(fixture.session.matchingTab(for: address("https://example.com/docs"))?.tab == second)
    }

    @Test func aTabNotLoadedSinceLaunchMatchesByItsLastSavedAddress() async throws {
        let database = TemporaryDatabase()
        let before = SessionFixture()
        let first = before.visit("https://example.com/docs/api")
        before.visit("https://swift.org")
        let autosave = SessionAutosave(session: before.session, database: try database.open())
        await autosave.saveNow()

        let after = SessionFixture()
        after.session.restore(try database.open().savedSession())
        #expect(after.createdPageCount == 1)

        let match = after.session.matchingTab(for: address("HTTPS://Example.com/docs/api/?utm_medium=x#y"))
        #expect(match?.tab == first)
        #expect(after.createdPageCount == 1)

        #expect(after.session.focus(match!, openedFrom: URL(string: "https://example.com/docs/api")!))
        #expect(after.session.selectedTabID == first)
        #expect(after.createdPageCount == 2)
        #expect(after.pages[first]?.state.url?.absoluteString == "https://example.com/docs/api")
    }

    @Test func aPinnedTabMatchesAndSoDoesOneInsideAFolderCollapsedOrNot() {
        let fixture = SessionFixture()
        let pinned = fixture.visit("https://example.com/pinned")
        let inFolder = fixture.visit("https://example.com/folder")
        let inSubFolder = fixture.visit("https://example.com/sub")
        fixture.visit("https://swift.org")
        [pinned, inFolder, inSubFolder].forEach { fixture.session.pin($0) }
        let docs = fixture.session.createFolder(name: "Docs")!
        let more = fixture.session.createFolder(name: "More", in: docs)!
        fixture.session.movePinned(.tab(inFolder), into: docs)
        fixture.session.movePinned(.tab(inSubFolder), into: more)
        fixture.session.setFolderExpanded(more, false)
        fixture.session.setFolderExpanded(docs, false)

        #expect(fixture.session.matchingTab(for: address("https://example.com/pinned?utm_source=mail"))?.tab == pinned)
        #expect(fixture.session.matchingTab(for: address("https://example.com/folder#top"))?.tab == inFolder)
        #expect(fixture.session.matchingTab(for: address("https://EXAMPLE.com/sub/"))?.tab == inSubFolder)
    }

    @Test func aPinnedTabClosedToItsLastAddressStillMatchesAndFocusingItWakesIt() throws {
        let fixture = SessionFixture()
        let id = fixture.visit("https://example.com/docs")
        fixture.visit("https://swift.org")
        fixture.session.pin(id)
        fixture.session.close(id)
        #expect(fixture.pages[id]?.isClosed == true)

        let match = try #require(fixture.session.matchingTab(for: address("https://example.com/docs#intro")))
        #expect(match.tab == id)

        #expect(fixture.session.focus(match, openedFrom: URL(string: "https://example.com/docs#intro")!))
        #expect(fixture.session.selectedTabID == id)
        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://example.com/docs")
    }

    @Test func aPinnedTabOfAnotherSpaceMatchesAndFocusingItSwitchesSpace() {
        let fixture = SessionFixture()
        let home = fixture.session.activeSpaceID
        let id = fixture.visit("https://example.com/docs")
        fixture.session.pin(id)
        fixture.session.createSpace(name: "Reading", emoji: "📚")
        fixture.visit("https://swift.org")

        let match = fixture.session.matchingTab(for: address("https://example.com/docs"))

        #expect(match == MatchingTab(profile: fixture.session.profileID, space: home, tab: id))
    }

    // MARK: Banner

    @Test func focusingAMatchingTabRaisesABannerThatCarriesTheLinkAsSent() throws {
        let fixture = SessionFixture()
        let id = fixture.visit("https://example.com/docs")
        fixture.visit("https://swift.org")
        let link = URL(string: "https://example.com/docs?utm_source=mail#intro")!

        fixture.session.focus(fixture.session.matchingTab(for: address(link.absoluteString))!, openedFrom: link)

        let banner = try #require(fixture.session.matchBanner)
        #expect(banner.tab == id)
        #expect(banner.link == link)
        #expect(fixture.session.selectedTabID == id)
    }

    @Test func theBannerOpensTheLinkInANewTabSelectedAndTakesItselfDown() throws {
        let fixture = SessionFixture()
        let id = fixture.visit("https://example.com/docs")
        let link = URL(string: "https://example.com/docs?utm_source=mail#intro")!
        fixture.session.focus(fixture.session.matchingTab(for: address(link.absoluteString))!, openedFrom: link)

        let opened = try #require(fixture.session.openMatchBannerLinkInNewTab())

        #expect(opened != id)
        #expect(fixture.session.tabs.map(\.id) == [id, opened])
        #expect(fixture.session.selectedTabID == opened)
        #expect(fixture.session.selectedTab?.address == link)
        #expect(fixture.session.matchBanner == nil)
        #expect(fixture.session.openMatchBannerLinkInNewTab() == nil)
    }

    @Test func dismissingTheBannerOpensNothing() {
        let fixture = SessionFixture()
        let link = URL(string: "https://example.com/docs")!
        fixture.visit(link.absoluteString)
        fixture.session.focus(fixture.session.matchingTab(for: address(link.absoluteString))!, openedFrom: link)

        fixture.session.dismissMatchBanner()

        #expect(fixture.session.matchBanner == nil)
        #expect(fixture.session.tabs.count == 1)
    }

    @Test func showingAnotherTabTakesTheBannerDown() {
        let fixture = SessionFixture()
        let link = URL(string: "https://example.com/docs")!
        let matching = fixture.visit(link.absoluteString)
        let other = fixture.visit("https://swift.org")
        fixture.session.focus(fixture.session.matchingTab(for: address(link.absoluteString))!, openedFrom: link)

        fixture.session.select(other)
        #expect(fixture.session.matchBanner == nil)

        fixture.session.select(matching)
        #expect(fixture.session.matchBanner == nil)
    }

    @Test func switchingSpaceOrClosingTheMatchingTabTakesTheBannerDown() {
        let fixture = SessionFixture()
        let link = URL(string: "https://example.com/docs")!
        fixture.visit(link.absoluteString)
        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")
        fixture.visit("https://swift.org")
        fixture.session.focus(fixture.session.matchingTab(for: address(link.absoluteString))!, openedFrom: link)
        #expect(fixture.session.matchBanner != nil)

        fixture.session.selectSpace(reading)
        #expect(fixture.session.matchBanner == nil)

        fixture.session.focus(fixture.session.matchingTab(for: address(link.absoluteString))!, openedFrom: link)
        fixture.session.closeSelectedTab()
        #expect(fixture.session.matchBanner == nil)
    }

    @Test func aMatchFromAnotherProfileOrAClosedTabIsRefused() {
        let fixture = SessionFixture()
        let id = fixture.visit("https://example.com/docs")
        let link = URL(string: "https://example.com/docs")!
        let space = fixture.session.activeSpaceID
        let foreign = MatchingTab(profile: ProfileID(rawValue: UUID()), space: space, tab: id)
        let match = fixture.session.matchingTab(for: address(link.absoluteString))!
        fixture.session.close(id)

        #expect(!fixture.session.focus(foreign, openedFrom: link))
        #expect(!fixture.session.focus(match, openedFrom: link))
        #expect(fixture.session.matchBanner == nil)
    }
}
