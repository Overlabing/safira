// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
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
    session.spaces.map { "\($0.emoji) \($0.name)" }
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

    @Test func aNewSpaceComesLastIsShownAndStartsWithNoTab() {
        let fixture = SessionFixture()
        let homeTabs = openTabs(fixture, ["a.com", "b.com"])

        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")

        #expect(names(fixture.session) == ["🏠 Home", "📚 Reading"])
        #expect(fixture.session.activeSpaceID == reading)
        #expect(fixture.session.tabs.isEmpty)
        #expect(fixture.session.selectedTab == nil)
        #expect(fixture.session.spaces[0].tabs.map(\.id) == homeTabs)
    }

    @Test func aTabOpensInTheActiveSpace() {
        let fixture = SessionFixture()
        _ = openTabs(fixture, ["a.com"])
        fixture.session.createSpace(name: "Reading", emoji: "📚")

        let id = openTabs(fixture, ["b.com"])[0]

        #expect(fixture.session.spaces.map { $0.tabs.map { $0.address?.absoluteString } }
            == [["https://a.com"], ["https://b.com"]])
        #expect(fixture.session.selectedTabID == id)
    }

    @Test func aBlankNameOrEmojiFallsBackToTheDefaults() {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session

        session.createSpace(name: "  ", emoji: "")

        #expect(names(session) == ["🏠 Home", "🏠 Home"])
    }

    @Test func renamingChangesTheNameAndTheEmoji() {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let id = session.createSpace(name: "Reading", emoji: "📚")

        session.renameSpace(id, name: "  Research ", emoji: "🔬")

        #expect(names(session) == ["🏠 Home", "🔬 Research"])
    }

    @Test func renamingWithABlankFieldKeepsWhatWasThere() {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let id = session.spaces[0].id

        session.renameSpace(id, name: "", emoji: "🌿")
        session.renameSpace(id, name: "Garden", emoji: " ")

        #expect(names(session) == ["🌿 Garden"])
    }

    @Test func anEmojiKeepsItsFirstCharacterOnly() {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session

        session.renameSpace(session.spaces[0].id, name: "France", emoji: "🇫🇷🏠x")

        #expect(names(session) == ["🇫🇷 France"])
    }

    @Test func spacesAreReorderedAndAMoveStopsAtTheEnds() {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let home = session.spaces[0].id
        let reading = session.createSpace(name: "Reading", emoji: "📚")
        session.createSpace(name: "Work", emoji: "💼")

        session.moveSpace(home, to: 2)
        #expect(names(session) == ["📚 Reading", "💼 Work", "🏠 Home"])

        session.moveSpace(reading, by: 1)
        #expect(names(session) == ["💼 Work", "📚 Reading", "🏠 Home"])

        session.moveSpace(reading, by: -5)
        #expect(names(session) == ["📚 Reading", "💼 Work", "🏠 Home"])

        session.moveSpace(home, to: 99)
        #expect(names(session) == ["📚 Reading", "💼 Work", "🏠 Home"])
    }

    @Test func reorderingDoesNotChangeTheActiveSpace() {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let reading = session.createSpace(name: "Reading", emoji: "📚")

        session.moveSpace(reading, to: 0)

        #expect(session.activeSpaceID == reading)
    }

    @Test func eachSpaceKeepsItsOwnTabsAndSelection() {
        let fixture = SessionFixture()
        let home = fixture.session.spaces[0].id
        let homeTabs = openTabs(fixture, ["a.com", "b.com"])
        fixture.session.select(homeTabs[0])
        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")
        let readingTabs = openTabs(fixture, ["c.com"])

        fixture.session.selectSpace(home)
        #expect(fixture.session.tabs.map(\.id) == homeTabs)
        #expect(fixture.session.selectedTabID == homeTabs[0])

        fixture.session.selectSpace(reading)
        #expect(fixture.session.tabs.map(\.id) == readingTabs)
        #expect(fixture.session.selectedTabID == readingTabs[0])
    }

    @Test func switchingSpaceByOffsetWrapsAroundTheEnds() {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let home = session.spaces[0].id
        let reading = session.createSpace(name: "Reading", emoji: "📚")
        let work = session.createSpace(name: "Work", emoji: "💼")

        session.selectSpace(offset: 1)
        #expect(session.activeSpaceID == home)
        session.selectSpace(offset: 1)
        #expect(session.activeSpaceID == reading)
        session.selectSpace(offset: -2)
        #expect(session.activeSpaceID == work)
    }

    @Test func selectingATabOfAnotherSpaceShowsThatSpace() {
        let fixture = SessionFixture()
        let home = fixture.session.spaces[0].id
        let homeTab = openTabs(fixture, ["a.com"])[0]
        fixture.session.createSpace(name: "Reading", emoji: "📚")

        fixture.session.select(homeTab)

        #expect(fixture.session.activeSpaceID == home)
        #expect(fixture.session.selectedTabID == homeTab)
    }

    @Test func tabCommandsActOnTheActiveSpaceOnly() {
        let fixture = SessionFixture()
        let homeTabs = openTabs(fixture, ["a.com", "b.com"])
        fixture.session.createSpace(name: "Reading", emoji: "📚")
        let readingTabs = openTabs(fixture, ["c.com", "d.com"])

        fixture.session.move(readingTabs[1], to: 0)
        fixture.session.move(homeTabs[1], to: 0)
        fixture.session.closeSelectedTab()

        #expect(fixture.session.tabs.map(\.id) == [readingTabs[0]])
        #expect(fixture.session.spaces[0].tabs.map(\.id) == homeTabs)
    }

    @Test func aLinkOpenedFromABackgroundSpaceStaysInThatSpace() {
        let fixture = SessionFixture()
        let homeTab = openTabs(fixture, ["a.com"])[0]
        fixture.session.createSpace(name: "Reading", emoji: "📚")

        fixture.pages[homeTab]?.onNewTab?(.address(URL(string: "https://b.com")!))

        #expect(fixture.session.tabs.isEmpty)
        #expect(fixture.session.spaces[0].tabs.map { $0.address?.absoluteString } == ["https://a.com", "https://b.com"])
    }

    @Test func aReopenedTabGoesBackToItsSpace() {
        let fixture = SessionFixture()
        let home = fixture.session.spaces[0].id
        let homeTabs = openTabs(fixture, ["a.com", "b.com"])
        fixture.session.close(homeTabs[0])
        fixture.session.createSpace(name: "Reading", emoji: "📚")

        fixture.session.reopenClosedTab()

        #expect(fixture.session.activeSpaceID == home)
        #expect(fixture.session.tabs.map { $0.address?.absoluteString } == ["https://a.com", "https://b.com"])
    }

    @Test func deletingASpaceClosesItsTabsAndLeavesTheOtherSpacesAlone() {
        let fixture = SessionFixture()
        let homeTabs = openTabs(fixture, ["a.com"])
        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")
        let readingTabs = openTabs(fixture, ["b.com", "c.com"])

        fixture.session.deleteSpace(reading)

        #expect(names(fixture.session) == ["🏠 Home"])
        #expect(readingTabs.map { fixture.pages[$0]?.isClosed } == [true, true])
        #expect(fixture.pages[homeTabs[0]]?.isClosed == false)
        #expect(fixture.session.tabs.map(\.id) == homeTabs)
        #expect(fixture.session.canReopenClosedTab == false)
    }

    @Test func deletingTheActiveSpaceShowsTheOneBeforeItOrTheNextWhenItWasFirst() {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let home = session.spaces[0].id
        let reading = session.createSpace(name: "Reading", emoji: "📚")
        let work = session.createSpace(name: "Work", emoji: "💼")

        session.selectSpace(reading)
        session.deleteSpace(reading)
        #expect(session.activeSpaceID == home)

        session.deleteSpace(home)
        #expect(session.activeSpaceID == work)
    }

    @Test func deletingAnInactiveSpaceKeepsTheActiveOne() {
        let sessionFixture = SessionFixture()
        let session: ProfileSession = sessionFixture.session
        let home = session.spaces[0].id
        let reading = session.createSpace(name: "Reading", emoji: "📚")

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

    @Test func aDeletedSpaceTabClosedEarlierReopensInTheActiveSpace() {
        let fixture = SessionFixture()
        let home = fixture.session.spaces[0].id
        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")
        let readingTab = openTabs(fixture, ["b.com"])[0]
        fixture.session.close(readingTab)
        fixture.session.deleteSpace(reading)

        fixture.session.reopenClosedTab()

        #expect(fixture.session.activeSpaceID == home)
        #expect(fixture.session.tabs.map { $0.address?.absoluteString } == ["https://b.com"])
    }

    @Test func spacesOfTwoProfilesAreIndependent() {
        let workFixture = SessionFixture()
        let work: ProfileSession = workFixture.session
        let personalFixture = SessionFixture()
        let personal: ProfileSession = personalFixture.session

        work.createSpace(name: "Clients", emoji: "💼")

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
        let reading = before.session.createSpace(name: "Reading", emoji: "📚")
        let readingTabs = openTabs(before, ["c.com"])
        let work = before.session.createSpace(name: "Work", emoji: "💼")
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
        before.session.createSpace(name: "Reading", emoji: "📚")
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
        let reading = before.session.createSpace(name: "Reading", emoji: "📚")
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
        let autosave = SessionAutosave(session: fixture.session, database: try database.open(), delay: .milliseconds(10))
        autosave.start()
        await autosave.saveNow()
        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")
        fixture.session.renameSpace(reading, name: "Research", emoji: "🔬")

        let reader = try database.open()
        let deadline = ContinuousClock.now + .seconds(5)
        while try reader.savedSession().activeSpace?.name != "Research", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        autosave.stop()

        let saved = try reader.savedSession()
        #expect(saved.spaces.map { "\($0.emoji) \($0.name)" } == ["🏠 Home", "🔬 Research"])
        #expect(saved.activeSpaceID == reading)
    }
}
