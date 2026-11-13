// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing
@testable import SafiraSession

/// While the Command bar is open for a new Tab, the sidebar shows the New Tab row as selected, not the Tab whose page
/// stays on screen; closing it gives the selection back, and opening something selects the Tab it went to.
@MainActor
@Suite struct SidebarSelectionTests {
    @Test(arguments: [true, false])
    func theSelectedTabIsTheSelectedRow(hasSpaces: Bool) {
        let fixture = SessionFixture(hasSpaces: hasSpaces)
        let shown = fixture.visit("example.com")

        #expect(fixture.session.sidebarSelection == .tab(shown))
    }

    @Test func noTabMeansNoSelectedRow() {
        let fixture = SessionFixture()

        #expect(fixture.session.sidebarSelection == .none)
    }

    @Test(arguments: [true, false])
    func openingTheCommandBarForANewTabSelectsTheNewTabRowAndKeepsThePage(hasSpaces: Bool) {
        let fixture = SessionFixture(hasSpaces: hasSpaces)
        let shown = fixture.visit("example.com")

        fixture.session.openCommandBar(for: .newTab)

        #expect(fixture.session.sidebarSelection == .newTab)
        #expect(fixture.session.selectedTabID == shown)
        #expect(fixture.session.tabs.count == 1)
    }

    @Test func editingTheShownTabsAddressKeepsItsRowSelected() {
        let fixture = SessionFixture()
        let shown = fixture.visit("example.com")

        fixture.session.openCommandBar(for: .selectedTab)

        #expect(fixture.session.sidebarSelection == .tab(shown))
    }

    @Test(arguments: [true, false])
    func escapeOrAClickAwayGivesTheSelectionBackToThePreviousTab(hasSpaces: Bool) {
        let fixture = SessionFixture(hasSpaces: hasSpaces)
        let first = fixture.visit("example.com")
        let previous = fixture.visit("example.org")
        fixture.session.select(first)
        fixture.session.select(previous)
        fixture.session.openCommandBar(for: .newTab)

        fixture.session.dismissCommandBar()

        #expect(fixture.session.sidebarSelection == .tab(previous))
        #expect(fixture.session.tabs.count == 2)
    }

    @Test(arguments: [true, false])
    func enterCreatesTheTabAndSelectsItsRow(hasSpaces: Bool) {
        let fixture = SessionFixture(hasSpaces: hasSpaces)
        let previous = fixture.visit("example.com")
        fixture.session.openCommandBar(for: .newTab)

        fixture.session.submitCommandBar("example.org")

        let created = fixture.session.tabs.last!.id
        #expect(created != previous)
        #expect(fixture.session.tabs.count == 2)
        #expect(fixture.session.sidebarSelection == .tab(created))
        #expect(fixture.session.selectedTab?.address == URL(string: "https://example.org"))
    }

    @Test func enterWithBlankTextCreatesNothingAndGivesTheSelectionBack() {
        let fixture = SessionFixture()
        let previous = fixture.visit("example.com")
        fixture.session.openCommandBar(for: .newTab)

        fixture.session.submitCommandBar("  ")

        #expect(fixture.session.tabs.count == 1)
        #expect(fixture.session.sidebarSelection == .tab(previous))
    }

    @Test func choosingAnOpenTabSuggestionSwitchesToItsRow() {
        let fixture = SessionFixture()
        let first = fixture.visit("example.com", titled: "Example")
        fixture.visit("example.org", titled: "Other")
        fixture.session.openCommandBar(for: .newTab)

        fixture.session.openSuggestion(
            CommandBarSuggestion(kind: .openTab(first), title: "Example", address: URL(string: "https://example.com")!))

        #expect(fixture.session.sidebarSelection == .tab(first))
        #expect(fixture.session.tabs.count == 2)
    }

    @Test func choosingAHistorySuggestionOpensANewTabAndSelectsIt() {
        let fixture = SessionFixture()
        fixture.visit("example.com")
        fixture.session.openCommandBar(for: .newTab)

        fixture.session.openSuggestion(CommandBarSuggestion(
            kind: .history(URL(string: "https://example.net")!), title: "Net", address: URL(string: "https://example.net")!))

        let created = fixture.session.tabs.last!.id
        #expect(fixture.session.tabs.count == 2)
        #expect(fixture.session.sidebarSelection == .tab(created))
    }
}
