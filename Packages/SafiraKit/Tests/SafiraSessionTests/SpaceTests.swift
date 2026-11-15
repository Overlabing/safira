// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Spaces
import Testing

@MainActor
private func openTabs(_ fixture: SessionFixture, _ addresses: [String]) -> [TabID] {
    addresses.map { address in
        fixture.session.openCommandBar(for: .newTab)
        fixture.session.submitCommandBar(address)
        return fixture.session.selectedTabID!
    }
}

@MainActor
private func names(_ session: ProfileSession) -> [String] {
    session.spaces.map { "\($0.icon.emoji ?? "-") \($0.name)" }
}

@MainActor
@Suite struct SpaceTests {
    @Test func aProfileStartsWithOneActiveSpace() {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session

        #expect(names(session) == ["🏠 Home"])
        #expect(session.activeSpaceID == session.spaces[0].id)
        #expect(session.tabs.isEmpty)
    }

    @Test func aNewSpaceComesLastIsShownAndStartsWithNoTab() throws {
        let fixture = SessionFixture()
        let homeTabs = openTabs(fixture, ["a.com", "b.com"])

        let reading = try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))

        #expect(names(fixture.session) == ["🏠 Home", "📚 Reading"])
        #expect(fixture.session.activeSpaceID == reading)
        #expect(fixture.session.tabs.isEmpty)
        #expect(fixture.session.selectedTab == nil)
        #expect(fixture.session.spaces[0].tabs.map(\.id) == homeTabs)
    }

    @Test func aTabOpensInTheActiveSpace() throws {
        let fixture = SessionFixture()
        _ = openTabs(fixture, ["a.com"])
        try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))

        let id = openTabs(fixture, ["b.com"])[0]

        #expect(fixture.session.spaces.map { $0.tabs.map { $0.address?.absoluteString } }
            == [["https://a.com"], ["https://b.com"]])
        #expect(fixture.session.selectedTabID == id)
    }

    @Test func aBlankNameOrOneAnotherSpaceHasIsRefusedByTheSpaceRules() {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session

        #expect(throws: SpaceRuleError.emptyName) { try session.createSpace(name: "  ", icon: .emoji("📚")) }
        #expect(throws: SpaceRuleError.duplicateName("home")) { try session.createSpace(name: " home ") }

        #expect(names(session) == ["🏠 Home"])
    }

    @Test func editingChangesTheNameTheIconAndKeepsTheThemeWithoutOne() throws {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let id = try session.createSpace(name: "Reading", icon: .emoji("📚"), paletteID: "mint-cyan")

        try session.editSpace(id, name: "  Research ", icon: .symbol("book"))

        #expect(session.spaces.map(\.name) == ["Home", "Research"])
        #expect(session.spaces.map(\.icon) == [.emoji("🏠"), .symbol("book")])
        #expect(session.spaces[1].paletteID == "mint-cyan")
    }

    @Test func anEditKeepsTheSpacesOwnNameButRefusesABlankOneOrAnothersAndChangesNothing() throws {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let home = session.spaces[0].id
        try session.createSpace(name: "Reading", icon: .emoji("📚"))

        try session.editSpace(home, name: "HOME", icon: .initial)
        #expect(throws: SpaceRuleError.emptyName) { try session.editSpace(home, name: " ", icon: .emoji("🌿")) }
        #expect(throws: SpaceRuleError.duplicateName("reading")) {
            try session.editSpace(home, name: "reading", icon: .emoji("🌿"))
        }

        #expect(session.spaces.map(\.name) == ["HOME", "Reading"])
        #expect(session.spaces.map(\.icon) == [.initial, .emoji("📚")])
    }

    @Test func aNewOrderOfEveryOneOfTheProfilesSpacesIsKeptAndAnyOtherRefused() throws {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let home = session.spaces[0].id
        let reading = try session.createSpace(name: "Reading", icon: .emoji("📚"))
        let work = try session.createSpace(name: "Work", icon: .emoji("💼"))

        #expect(session.reorderSpaces([work, home, reading]))
        #expect(names(session) == ["💼 Work", "🏠 Home", "📚 Reading"])
        #expect(!session.reorderSpaces([home, reading]))
        #expect(!session.reorderSpaces([home, home, reading]))
        #expect(!session.reorderSpaces([home, reading, SpaceID()]))
        #expect(names(session) == ["💼 Work", "🏠 Home", "📚 Reading"])
        #expect(session.activeSpaceID == work)
    }

    @Test func spacesAreReorderedAndAMoveStopsAtTheEnds() throws {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let home = session.spaces[0].id
        let reading = try session.createSpace(name: "Reading", icon: .emoji("📚"))
        try session.createSpace(name: "Work", icon: .emoji("💼"))

        session.moveSpace(home, to: 2)
        #expect(names(session) == ["📚 Reading", "💼 Work", "🏠 Home"])

        session.moveSpace(reading, by: 1)
        #expect(names(session) == ["💼 Work", "📚 Reading", "🏠 Home"])

        session.moveSpace(reading, by: -5)
        #expect(names(session) == ["📚 Reading", "💼 Work", "🏠 Home"])

        session.moveSpace(home, to: 99)
        #expect(names(session) == ["📚 Reading", "💼 Work", "🏠 Home"])
    }

    @Test func reorderingDoesNotChangeTheActiveSpace() throws {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let reading = try session.createSpace(name: "Reading", icon: .emoji("📚"))

        session.moveSpace(reading, to: 0)

        #expect(session.activeSpaceID == reading)
    }

    @Test func eachSpaceKeepsItsOwnTabsAndSelection() throws {
        let fixture = SessionFixture()
        let home = fixture.session.spaces[0].id
        let homeTabs = openTabs(fixture, ["a.com", "b.com"])
        fixture.session.select(homeTabs[0])
        let reading = try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))
        let readingTabs = openTabs(fixture, ["c.com"])

        fixture.session.selectSpace(home)
        #expect(fixture.session.tabs.map(\.id) == homeTabs)
        #expect(fixture.session.selectedTabID == homeTabs[0])

        fixture.session.selectSpace(reading)
        #expect(fixture.session.tabs.map(\.id) == readingTabs)
        #expect(fixture.session.selectedTabID == readingTabs[0])
    }

    @Test func switchingSpaceByOffsetWrapsAroundTheEnds() throws {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let home = session.spaces[0].id
        let reading = try session.createSpace(name: "Reading", icon: .emoji("📚"))
        let work = try session.createSpace(name: "Work", icon: .emoji("💼"))

        session.selectSpace(offset: 1)
        #expect(session.activeSpaceID == home)
        session.selectSpace(offset: 1)
        #expect(session.activeSpaceID == reading)
        session.selectSpace(offset: -2)
        #expect(session.activeSpaceID == work)
    }

    @Test func selectingATabOfAnotherSpaceShowsThatSpace() throws {
        let fixture = SessionFixture()
        let home = fixture.session.spaces[0].id
        let homeTab = openTabs(fixture, ["a.com"])[0]
        try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))

        fixture.session.select(homeTab)

        #expect(fixture.session.activeSpaceID == home)
        #expect(fixture.session.selectedTabID == homeTab)
    }

    @Test func tabCommandsActOnTheActiveSpaceOnly() throws {
        let fixture = SessionFixture()
        let homeTabs = openTabs(fixture, ["a.com", "b.com"])
        try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))
        let readingTabs = openTabs(fixture, ["c.com", "d.com"])

        fixture.session.move(readingTabs[1], to: 0)
        fixture.session.move(homeTabs[1], to: 0)
        fixture.session.closeSelectedTab()

        #expect(fixture.session.tabs.map(\.id) == [readingTabs[0]])
        #expect(fixture.session.spaces[0].tabs.map(\.id) == homeTabs)
    }

    @Test func aLinkOpenedFromABackgroundSpaceStaysInThatSpace() throws {
        let fixture = SessionFixture()
        let homeTab = openTabs(fixture, ["a.com"])[0]
        try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))

        fixture.pages[homeTab]?.onNewTab?(.address(URL(string: "https://b.com")!))

        #expect(fixture.session.tabs.isEmpty)
        #expect(fixture.session.spaces[0].tabs.map { $0.address?.absoluteString } == ["https://a.com", "https://b.com"])
    }

    @Test func aReopenedTabGoesBackToItsSpace() throws {
        let fixture = SessionFixture()
        let home = fixture.session.spaces[0].id
        let homeTabs = openTabs(fixture, ["a.com", "b.com"])
        fixture.session.close(homeTabs[0])
        try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))

        fixture.session.reopenClosedTab()

        #expect(fixture.session.activeSpaceID == home)
        #expect(fixture.session.tabs.map { $0.address?.absoluteString } == ["https://a.com", "https://b.com"])
    }

    @Test func deletingASpaceClosesItsTabsAndLeavesTheOtherSpacesAlone() throws {
        let fixture = SessionFixture()
        let homeTabs = openTabs(fixture, ["a.com"])
        let reading = try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))
        let readingTabs = openTabs(fixture, ["b.com", "c.com"])

        fixture.session.deleteSpace(reading)

        #expect(names(fixture.session) == ["🏠 Home"])
        #expect(readingTabs.map { fixture.pages[$0]?.isClosed } == [true, true])
        #expect(fixture.pages[homeTabs[0]]?.isClosed == false)
        #expect(fixture.session.tabs.map(\.id) == homeTabs)
        #expect(fixture.session.canReopenClosedTab == false)
    }

    @Test func deletingTheActiveSpaceShowsTheOneBeforeItOrTheNextWhenItWasFirst() throws {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let home = session.spaces[0].id
        let reading = try session.createSpace(name: "Reading", icon: .emoji("📚"))
        let work = try session.createSpace(name: "Work", icon: .emoji("💼"))

        session.selectSpace(reading)
        session.deleteSpace(reading)
        #expect(session.activeSpaceID == home)

        session.deleteSpace(home)
        #expect(session.activeSpaceID == work)
    }

    @Test func deletingAnInactiveSpaceKeepsTheActiveOne() throws {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let home = session.spaces[0].id
        let reading = try session.createSpace(name: "Reading", icon: .emoji("📚"))

        session.deleteSpace(home)

        #expect(session.activeSpaceID == reading)
        #expect(names(session) == ["📚 Reading"])
    }

    @Test func theLastSpaceOfAProfileCannotBeDeleted() {
        let fixture = SessionFixture()
        let tabs = openTabs(fixture, ["a.com"])

        #expect(fixture.session.canDeleteSpace == false)
        fixture.session.deleteSpace(fixture.session.spaces[0].id)

        #expect(names(fixture.session) == ["🏠 Home"])
        #expect(fixture.session.tabs.map(\.id) == tabs)
    }

    @Test func aDeletedSpaceTabClosedEarlierReopensInTheActiveSpace() throws {
        let fixture = SessionFixture()
        let home = fixture.session.spaces[0].id
        let reading = try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))
        let readingTab = openTabs(fixture, ["b.com"])[0]
        fixture.session.close(readingTab)
        fixture.session.deleteSpace(reading)

        fixture.session.reopenClosedTab()

        #expect(fixture.session.activeSpaceID == home)
        #expect(fixture.session.tabs.map { $0.address?.absoluteString } == ["https://b.com"])
    }

    @Test func spacesOfTwoProfilesAreIndependent() throws {
        let workFixture = SessionFixture()
        let work: ProfileSession = workFixture.session
        let personalFixture = SessionFixture()
        let personal: ProfileSession = personalFixture.session

        try work.createSpace(name: "Clients", icon: .emoji("💼"))

        #expect(names(work) == ["🏠 Home", "💼 Clients"])
        #expect(names(personal) == ["🏠 Home"])
    }
}

@MainActor
@Suite struct SpaceRestorationTests {
    private func relaunch(from database: TemporaryDatabase) throws -> SessionFixture {
        let fixture = SessionFixture()
        fixture.session.restore(try database.open().savedSession())
        return fixture
    }

    @Test func spacesTheirTabsAndTheLastActiveSpaceComeBackAfterARelaunch() async throws {
        let database = TemporaryDatabase()
        let before = SessionFixture()
        let homeTabs = openTabs(before, ["a.com", "b.com"])
        let reading = try before.session.createSpace(name: "Reading", icon: .emoji("📚"))
        let readingTabs = openTabs(before, ["c.com"])
        let work = try before.session.createSpace(name: "Work", icon: .emoji("💼"))
        before.session.moveSpace(work, to: 0)
        before.session.selectSpace(reading)
        await SessionAutosave(session: before.session, database: try database.open()).saveNow()

        let after = try relaunch(from: database)

        #expect(names(after.session) == ["💼 Work", "🏠 Home", "📚 Reading"])
        #expect(after.session.activeSpaceID == reading)
        #expect(after.session.tabs.map(\.id) == readingTabs)
        #expect(after.session.spaces[1].tabs.map(\.id) == homeTabs)
        #expect(after.session.spaces[1].selectedTabID == homeTabs[1])
    }

    @Test func onlyTheSelectedTabOfTheActiveSpaceGetsAPageUntilAnotherSpaceIsShown() async throws {
        let database = TemporaryDatabase()
        let before = SessionFixture()
        let home = before.session.spaces[0].id
        let homeTabs = openTabs(before, ["a.com", "b.com"])
        try before.session.createSpace(name: "Reading", icon: .emoji("📚"))
        let readingTab = openTabs(before, ["c.com"])[0]
        await SessionAutosave(session: before.session, database: try database.open()).saveNow()

        let after = try relaunch(from: database)
        #expect(Array(after.pages.keys) == [readingTab])

        after.session.selectSpace(home)
        #expect(Set(after.pages.keys) == [readingTab, homeTabs[1]])
        #expect(after.selectedPage?.restoreCount == 1)
    }

    @Test func aDeletedSpaceDoesNotReturnAfterARelaunch() async throws {
        let database = TemporaryDatabase()
        let before = SessionFixture()
        _ = openTabs(before, ["a.com"])
        let reading = try before.session.createSpace(name: "Reading", icon: .emoji("📚"))
        _ = openTabs(before, ["b.com"])
        await SessionAutosave(session: before.session, database: try database.open()).saveNow()
        before.session.deleteSpace(reading)
        await SessionAutosave(session: before.session, database: try database.open()).saveNow()

        let after = try relaunch(from: database)

        #expect(names(after.session) == ["🏠 Home"])
        #expect(after.addresses == ["https://a.com"])
    }

    @Test func aSpaceChangeIsSavedShortlyAfterwardsWithoutAskingForIt() async throws {
        let database = TemporaryDatabase()
        let fixture = SessionFixture()
        let connection = try database.open()
        let autosave = SessionAutosave(session: fixture.session, database: connection, delay: .milliseconds(10))
        autosave.start()
        await autosave.saveNow()
        let reading = try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))
        try fixture.session.editSpace(reading, name: "Research", icon: .emoji("🔬"))

        let latest = try await waitForSave({ try connection.savedSession() }, until: { $0.activeSpace?.name == "Research" })
        autosave.stop()

        let saved = try #require(latest)
        #expect(saved.spaces.map { "\($0.icon.emoji ?? "-") \($0.name)" } == ["🏠 Home", "🔬 Research"])
        #expect(saved.activeSpaceID == reading)
    }
}
