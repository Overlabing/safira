// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

/// ⌘1…⌘9 show a Tab by its place in the sidebar, ⌃1…⌃9 a Space by its place in the Space rail.
@MainActor
@Suite struct NumberedSelectionTests {
    private func open(_ fixture: SessionFixture, _ addresses: [String]) -> [TabID] {
        addresses.map { fixture.visit($0) }
    }

    @Test func aNumberShowsThatTabOfTheActiveSpace() {
        let fixture = SessionFixture()
        let ids = open(fixture, ["a.com", "b.com", "c.com"])

        fixture.session.selectTab(number: 2)

        #expect(fixture.session.selectedTabID == ids[1])
        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://b.com")
    }

    @Test func pinnedTabsCountFirstAsTheSidebarShowsThem() {
        let fixture = SessionFixture()
        let ids = open(fixture, ["a.com", "b.com", "c.com"])
        fixture.session.pin(ids[2])

        fixture.session.selectTab(number: 1)
        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://c.com")

        fixture.session.selectTab(number: 3)
        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://b.com")
    }

    @Test func aNumberPastTheLastTabChangesNothing() {
        let fixture = SessionFixture()
        let ids = open(fixture, ["a.com", "b.com"])

        fixture.session.selectTab(number: 9)
        fixture.session.selectTab(number: 0)

        #expect(fixture.session.selectedTabID == ids[1])
    }

    @Test func tabNumbersStayInTheActiveSpace() {
        let fixture = SessionFixture()
        _ = open(fixture, ["a.com", "b.com"])
        fixture.session.createSpace(name: "Reading", emoji: "📚")
        let reading = open(fixture, ["c.com"])

        fixture.session.selectTab(number: 2)

        #expect(fixture.session.selectedTabID == reading[0])
        #expect(fixture.session.activeSpace.name == "Reading")
    }

    @Test func aNumberShowsThatSpace() {
        let fixture = SessionFixture()
        let home = fixture.session.activeSpaceID
        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")
        fixture.session.createSpace(name: "Work", emoji: "💼")

        fixture.session.selectSpace(number: 2)
        #expect(fixture.session.activeSpaceID == reading)

        fixture.session.selectSpace(number: 1)
        #expect(fixture.session.activeSpaceID == home)
        #expect(fixture.session.activeSpace.name == "Home")
    }

    @Test func aNumberPastTheLastSpaceChangesNothing() {
        let fixture = SessionFixture()
        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")

        fixture.session.selectSpace(number: 3)
        fixture.session.selectSpace(number: 0)

        #expect(fixture.session.activeSpaceID == reading)
    }
}
