// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

private let signIn = URL(string: "https://accounts.example/signin")!

/// Opens one Tab per address, in order.
@MainActor
private func openTabs(_ fixture: SessionFixture, _ addresses: [String]) {
    for address in addresses {
        fixture.session.openCommandBar(for: .newTab)
        fixture.session.submitCommandBar(address)
    }
}

@MainActor
@Suite struct PopupTests {
    @Test func aPopupOpenedWithWindowFeaturesIsAPopupOfItsOpenerAndNotATab() throws {
        let fixture = SessionFixture()
        openTabs(fixture, ["app.example"])
        let opener = try #require(fixture.session.selectedTabID)

        let (id, page) = fixture.openPopup(from: fixture.selectedPage, to: signIn,
                                           window: RequestedWindow(width: 480, height: 640))

        let popup = try #require(fixture.session.popups.first)
        #expect(fixture.session.popups.count == 1)
        #expect(popup.id == id)
        #expect(popup.openerTabID == opener)
        #expect(popup.requestedWindow == RequestedWindow(width: 480, height: 640))
        #expect(popup.state.url == signIn)
        #expect(fixture.addresses == ["https://app.example"])
        #expect(fixture.session.selectedTabID == opener)
        #expect(!page.isClosed)
    }

    @Test func aLinkOpenedWithoutWindowFeaturesStillOpensABackgroundTabRightAfterItsOpener() throws {
        let fixture = SessionFixture()
        openTabs(fixture, ["app.example", "other.example"])
        let first = try #require(fixture.session.tabs.first?.id)
        fixture.session.select(first)

        fixture.clickTargetBlankLink(in: fixture.selectedPage, to: URL(string: "https://docs.example/")!)

        #expect(fixture.addresses == ["https://app.example", "https://docs.example/", "https://other.example"])
        #expect(fixture.session.selectedTabID == first)
        #expect(fixture.session.popups.isEmpty)
    }

    @Test func aCommandClickInsideAPopupOpensABackgroundTabRightAfterTheTabThatOpenedIt() throws {
        let fixture = SessionFixture()
        openTabs(fixture, ["app.example", "other.example"])
        let first = try #require(fixture.session.tabs.first?.id)
        fixture.session.select(first)
        let (_, popupPage) = fixture.openPopup(from: fixture.selectedPage, to: signIn)

        popupPage.commandClickLink(to: URL(string: "https://help.example/")!)

        #expect(fixture.addresses == ["https://app.example", "https://help.example/", "https://other.example"])
        #expect(fixture.session.popups.count == 1)
    }

    @Test func aPopupEndsWhenItsPageClosesItself() {
        let fixture = SessionFixture()
        openTabs(fixture, ["app.example"])
        let (_, page) = fixture.openPopup(from: fixture.selectedPage, to: signIn)
        let popup = fixture.session.popups[0]

        page.closeWindow()

        #expect(fixture.session.popups.isEmpty)
        #expect(popup.isClosed)
        #expect(page.isClosed)
        #expect(fixture.addresses == ["https://app.example"])
    }

    @Test func theUserClosingAPopupClosesItsPage() {
        let fixture = SessionFixture()
        openTabs(fixture, ["app.example"])
        let (id, page) = fixture.openPopup(from: fixture.selectedPage, to: signIn)

        fixture.session.closePopup(id)
        fixture.session.closePopup(id)

        #expect(fixture.session.popups.isEmpty)
        #expect(page.isClosed)
    }

    @Test func closingTheOpenerClosesItsPopupsAndOnlyThose() throws {
        let fixture = SessionFixture()
        openTabs(fixture, ["app.example", "other.example"])
        let other = try #require(fixture.session.selectedTabID)
        let first = try #require(fixture.session.tabs.first?.id)
        fixture.session.select(first)
        let (_, fromFirst) = fixture.openPopup(from: fixture.selectedPage, to: signIn)
        fixture.session.select(other)
        let (kept, fromOther) = fixture.openPopup(from: fixture.selectedPage, to: signIn)

        fixture.session.close(first)

        #expect(fromFirst.isClosed)
        #expect(!fromOther.isClosed)
        #expect(fixture.session.popups.map(\.id) == [kept])
    }

    @Test func deletingTheSpaceOfTheOpenerClosesItsPopups() {
        let fixture = SessionFixture()
        fixture.session.createSpace(name: "Reading", emoji: "📚")
        let reading = fixture.session.activeSpaceID
        openTabs(fixture, ["app.example"])
        let (_, page) = fixture.openPopup(from: fixture.selectedPage, to: signIn)

        fixture.session.deleteSpace(reading)

        #expect(page.isClosed)
        #expect(fixture.session.popups.isEmpty)
    }

    @Test func closingEveryTabClosesEveryPopup() {
        let fixture = SessionFixture()
        openTabs(fixture, ["app.example"])
        let (_, page) = fixture.openPopup(from: fixture.selectedPage, to: signIn)

        fixture.session.closeAllTabs()

        #expect(page.isClosed)
        #expect(fixture.session.popups.isEmpty)
    }

    @Test func aPopupDoesNotBecomeASavedTab() {
        let fixture = SessionFixture()
        openTabs(fixture, ["app.example"])
        fixture.openPopup(from: fixture.selectedPage, to: signIn)

        #expect(fixture.session.savedSession().spaces.flatMap(\.tabs).map(\.address?.absoluteString)
            == ["https://app.example"])
    }
}
