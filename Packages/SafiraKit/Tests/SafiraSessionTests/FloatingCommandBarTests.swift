// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing
@testable import SafiraSession

/// The Command bar is a floating panel over the page: it is shown exactly while the session has a target for it.
@MainActor
@Suite struct FloatingCommandBarTests {
    @Test func theCommandBarStartsClosed() {
        let fixture = SessionFixture()

        #expect(fixture.session.isCommandBarOpen == false)
    }

    @Test func commandLOpensItForTheSelectedTab() {
        let fixture = SessionFixture()
        fixture.visit("example.com")

        fixture.session.openCommandBar(for: .selectedTab)

        #expect(fixture.session.isCommandBarOpen == true)
        #expect(fixture.session.commandBarTarget == .selectedTab)
    }

    @Test func commandTOpensItForANewTab() {
        let fixture = SessionFixture()
        fixture.visit("example.com")

        fixture.session.openCommandBar(for: .newTab)

        #expect(fixture.session.isCommandBarOpen == true)
        #expect(fixture.session.commandBarTarget == .newTab)
        #expect(fixture.session.tabs.count == 1)
    }

    @Test func returnWithAnAddressClosesItAndLoadsThePage() {
        let fixture = SessionFixture()
        fixture.visit("example.com")
        fixture.session.openCommandBar(for: .selectedTab)

        fixture.session.submitCommandBar("example.org")

        #expect(fixture.session.isCommandBarOpen == false)
        #expect(fixture.addresses == ["https://example.org"])
    }

    @Test func returnWithBlankTextClosesItAndOpensNothing() {
        let fixture = SessionFixture()
        fixture.visit("example.com")
        fixture.session.openCommandBar(for: .selectedTab)

        fixture.session.submitCommandBar("")

        #expect(fixture.session.isCommandBarOpen == false)
        #expect(fixture.addresses == ["https://example.com"])
    }

    @Test func escapeOrAnOutsideClickClosesItAndChangesNothing() {
        let fixture = SessionFixture()
        fixture.visit("example.com")
        fixture.session.openCommandBar(for: .newTab)

        fixture.session.dismissCommandBar()

        #expect(fixture.session.isCommandBarOpen == false)
        #expect(fixture.addresses == ["https://example.com"])
    }

    @Test func openingASuggestionClosesIt() {
        let fixture = SessionFixture()
        let first = fixture.visit("example.com", titled: "Example")
        fixture.visit("example.org", titled: "Other")
        fixture.session.openCommandBar(for: .newTab)

        fixture.session.openSuggestion(
            CommandBarSuggestion(kind: .openTab(first), title: "Example", address: URL(string: "https://example.com")!))

        #expect(fixture.session.isCommandBarOpen == false)
        #expect(fixture.session.selectedTabID == first)
    }

    @Test func aSearchWaitingForAnEngineLeavesItClosedWhileTheEngineIsChosen() {
        let fixture = SessionFixture()
        fixture.session.openCommandBar(for: .selectedTab)

        fixture.session.submitCommandBar("swift testing")

        #expect(fixture.session.isCommandBarOpen == false)
        #expect(fixture.session.searchAwaitingEngine == "swift testing")
    }
}
