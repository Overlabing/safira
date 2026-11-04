// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import Testing

/// A Profile database in a fresh folder, removed when the test ends.
final class TemporaryDatabase {
    let folder = FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)",
                                                                 directoryHint: .isDirectory)
    var file: URL { folder.appending(path: "profile.sqlite") }

    /// Opens the file as a relaunched app would: a new connection that knows nothing of the previous one.
    func open() throws -> ProfileDatabase {
        try ProfileDatabase(file: file)
    }

    deinit { try? FileManager.default.removeItem(at: folder) }
}

@MainActor
private func open(_ fixture: SessionFixture, _ addresses: [String]) -> [TabID] {
    addresses.map { address in
        fixture.session.openCommandBar(for: .newTab)
        fixture.session.submitCommandBar(address)
        return fixture.session.selectedTabID!
    }
}

/// Saves the fixture's Tabs as the autosave does, then drops everything but the database file, as `kill -9` would.
@MainActor
private func saveAndKill(_ fixture: SessionFixture, into database: TemporaryDatabase) async throws {
    let autosave = SessionAutosave(session: fixture.session, database: try database.open())
    await autosave.saveNow()
}

@MainActor
private func relaunch(from database: TemporaryDatabase, osBuild: String = "26A434",
                      preparePage: @escaping (SimulatedPage) -> Void = { _ in }) throws -> SessionFixture {
    let fixture = SessionFixture(osBuild: osBuild)
    fixture.preparePage = preparePage
    fixture.session.restore(try database.open().savedSession())
    return fixture
}

@MainActor
@Suite struct RelaunchTests {
    @Test func afterAKillEveryTabReturnsAndOnlyTheVisibleTabCreatesAPage() async throws {
        let database = TemporaryDatabase()
        let before = SessionFixture()
        let ids = open(before, ["a.com", "b.com", "c.com", "d.com"])
        before.session.select(ids[2])
        try await saveAndKill(before, into: database)

        let after = try relaunch(from: database)

        #expect(after.session.tabs.map(\.id) == ids)
        #expect(after.addresses == ["https://a.com", "https://b.com", "https://c.com", "https://d.com"])
        #expect(after.session.selectedTabID == ids[2])
        #expect(after.createdPageCount == 1)
        #expect(after.pages.keys.map { $0 } == [ids[2]])
        #expect(after.selectedPage?.restoreCount == 1)
        #expect(after.selectedPage?.loadCount == 0)
    }

    @Test func aDormantTabCreatesItsPageWhenFirstSelectedAndGetsItsHistoryBack() async throws {
        let database = TemporaryDatabase()
        let before = SessionFixture()
        let ids = open(before, ["a.com", "b.com"])
        before.pages[ids[0]]?.followLink(to: URL(string: "https://a.com/next")!)
        before.session.select(ids[1])
        try await saveAndKill(before, into: database)

        let after = try relaunch(from: database)
        after.session.select(ids[0])

        #expect(after.createdPageCount == 2)
        #expect(after.session.selectedTab?.address?.absoluteString == "https://a.com/next")
        #expect(after.session.selectedTab?.state.canGoBack == true)
        after.session.goBack()
        #expect(after.session.selectedTab?.address?.absoluteString == "https://a.com")
    }

    @Test func dormantTabsShowTheirSavedTitleAndAddressWithoutAPage() throws {
        let fixture = SessionFixture()
        let id = TabID()
        fixture.session.restore(SavedSession(tabs: [
            TabRecord(id: TabID(), address: URL(string: "https://a.com"), title: "A"),
            TabRecord(id: id, address: URL(string: "https://b.com"), title: "B"),
        ], selectedTabID: id))

        #expect(fixture.session.tabs[0].state == PageState(url: URL(string: "https://a.com"), title: "A"))
        #expect(fixture.session.tabs.map { $0.dormantRecord != nil } == [true, false])
        #expect(fixture.createdPageCount == 1)
    }

    @Test func closingTheVisibleTabWakesTheDormantTabThatTakesItsPlace() async throws {
        let database = TemporaryDatabase()
        let before = SessionFixture()
        let ids = open(before, ["a.com", "b.com", "c.com"])
        before.session.select(ids[1])
        try await saveAndKill(before, into: database)

        let after = try relaunch(from: database)
        after.session.closeSelectedTab()

        #expect(after.session.selectedTabID == ids[2])
        #expect(after.createdPageCount == 2)
        #expect(after.selectedPage?.state.url?.absoluteString == "https://c.com")
    }

    @Test func aDormantTabIsSavedAgainAsItWasRestored() async throws {
        let database = TemporaryDatabase()
        let before = SessionFixture()
        let ids = open(before, ["a.com", "b.com"])
        try await saveAndKill(before, into: database)
        let firstSave = try database.open().savedSession()

        let after = try relaunch(from: database)
        try await saveAndKill(after, into: database)

        #expect(after.session.tabs[0].dormantRecord != nil)
        #expect(try database.open().savedSession().tabs[0] == firstSave.tabs[0])
        #expect(firstSave.tabs.map(\.id) == ids)
        #expect(firstSave.tabs.map { $0.navigationState != nil } == [true, true])
    }

    @Test func aClosedTabDoesNotReturnAfterARelaunch() async throws {
        let database = TemporaryDatabase()
        let before = SessionFixture()
        let ids = open(before, ["a.com", "b.com", "c.com"])
        before.session.close(ids[1])
        try await saveAndKill(before, into: database)

        let after = try relaunch(from: database)

        #expect(after.addresses == ["https://a.com", "https://c.com"])
        #expect(after.session.canReopenClosedTab == false)
    }

    @Test func aProfileWithNoSavedTabsStartsEmpty() throws {
        let after = try relaunch(from: TemporaryDatabase())

        #expect(after.session.tabs.isEmpty)
        #expect(after.session.selectedTabID == nil)
        #expect(after.createdPageCount == 0)
    }
}

@MainActor
@Suite struct FallbackTests {
    @Test func aTabWhoseStateTheEngineRefusesLoadsItsLastAddress() async throws {
        let database = TemporaryDatabase()
        let before = SessionFixture()
        _ = open(before, ["a.com"])
        before.selectedPage?.followLink(to: URL(string: "https://a.com/last")!)
        try await saveAndKill(before, into: database)

        let after = try relaunch(from: database) { $0.refusesNavigationState = true }

        #expect(after.selectedPage?.restoreCount == 1)
        #expect(after.selectedPage?.loadCount == 1)
        #expect(after.session.selectedTab?.address?.absoluteString == "https://a.com/last")
        #expect(after.session.selectedTab?.state.canGoBack == false)
    }

    @Test func aStateWrittenByAnotherMacOSBuildIsNotRestoredAndTheLastAddressLoads() async throws {
        let database = TemporaryDatabase()
        let before = SessionFixture(osBuild: "26A434")
        _ = open(before, ["a.com"])
        before.selectedPage?.followLink(to: URL(string: "https://a.com/last")!)
        try await saveAndKill(before, into: database)

        let after = try relaunch(from: database, osBuild: "26B100")

        #expect(after.selectedPage?.restoreCount == 0)
        #expect(after.selectedPage?.loadCount == 1)
        #expect(after.session.selectedTab?.address?.absoluteString == "https://a.com/last")
    }

    @Test func restorationPrefersTheStateOfTheSameBuildThenTheAddress() throws {
        let state = Data("state".utf8)
        let address = try #require(URL(string: "https://a.com"))

        #expect(Restoration(TabRecord(id: TabID(), address: address, navigationState: state,
                                      navigationStateOSBuild: "26A434"), osBuild: "26A434")
            == .navigationState(state, fallback: address))
        #expect(Restoration(TabRecord(id: TabID(), address: address, navigationState: state,
                                      navigationStateOSBuild: "26A433"), osBuild: "26A434") == .address(address))
        #expect(Restoration(TabRecord(id: TabID(), address: address), osBuild: "26A434") == .address(address))
        #expect(Restoration(TabRecord(id: TabID()), osBuild: "26A434") == .blank)
    }
}

/// Decision D1: a page with a password field or a POST body is saved by its address only.
@MainActor
@Suite struct SensitivePageTests {
    @Test func anOrdinaryPageKeepsItsFullNavigationState() {
        let fixture = SessionFixture()
        _ = open(fixture, ["a.com"])
        fixture.selectedPage?.followLink(to: URL(string: "https://a.com/next")!)

        let record = fixture.session.savedSession().tabs[0]

        #expect(record.address?.absoluteString == "https://a.com/next")
        #expect(record.navigationState == fixture.selectedPage?.navigationState)
        #expect(record.navigationState != nil)
        #expect(record.navigationStateOSBuild == "26A434")
    }

    @Test func aPageWithAPasswordFieldIsSavedByItsAddressOnly() {
        let fixture = SessionFixture()
        _ = open(fixture, ["a.com/login"])
        fixture.selectedPage?.showPasswordField()

        #expect(fixture.session.savedSession().tabs
            == [TabRecord(id: fixture.session.selectedTabID!, address: URL(string: "https://a.com/login"))])
    }

    @Test func aPageReachedByAPostIsSavedByItsAddressOnly() {
        let fixture = SessionFixture()
        _ = open(fixture, ["a.com/form"])
        fixture.selectedPage?.submitPostForm(to: URL(string: "https://a.com/sent")!)

        #expect(fixture.session.savedSession().tabs
            == [TabRecord(id: fixture.session.selectedTabID!, address: URL(string: "https://a.com/sent"))])
    }

    @Test func aSensitivePageStillInTheHistoryKeepsTheStateOffTheDisk() {
        let fixture = SessionFixture()
        _ = open(fixture, ["a.com/login"])
        fixture.selectedPage?.showPasswordField()
        fixture.selectedPage?.followLink(to: URL(string: "https://a.com/home")!)

        let record = fixture.session.savedSession().tabs[0]

        #expect(record.address?.absoluteString == "https://a.com/home")
        #expect(record.navigationState == nil)
    }

    @Test func theFullStateComesBackOnceTheSensitivePageLeavesTheHistory() {
        let fixture = SessionFixture()
        _ = open(fixture, ["a.com"])
        fixture.selectedPage?.followLink(to: URL(string: "https://a.com/login")!)
        fixture.selectedPage?.showPasswordField()
        fixture.session.goBack()
        fixture.selectedPage?.followLink(to: URL(string: "https://a.com/other")!)

        #expect(fixture.session.savedSession().tabs[0].navigationState != nil)
    }

    @Test func theRuleKeepsTheStateOnlyWithoutSensitiveContent() {
        let state = Data("state".utf8)

        #expect(NavigationStateRule.savable(state, sensitiveContent: []) == state)
        #expect(NavigationStateRule.savable(state, sensitiveContent: .passwordField) == nil)
        #expect(NavigationStateRule.savable(state, sensitiveContent: .postBody) == nil)
        #expect(NavigationStateRule.savable(state, sensitiveContent: [.passwordField, .postBody]) == nil)
    }

    @Test func historyMarksAddUpAndGoWithTheirEntries() {
        var history = SensitiveHistory<Int>()
        history.mark(1, .passwordField)
        history.mark(2, .postBody)

        #expect(history.content(of: [1, 2, 3]) == [.passwordField, .postBody])
        #expect(history.content(of: [2, 3]) == .postBody)
        #expect(history.content(of: [1, 2, 3]) == .postBody)
        #expect(history.content(of: [3]) == [])
    }
}

@MainActor
@Suite struct AutosaveTests {
    @Test func aChangeIsSavedShortlyAfterwardsWithoutAskingForIt() async throws {
        let database = TemporaryDatabase()
        let fixture = SessionFixture()
        let autosave = SessionAutosave(session: fixture.session, database: try database.open(), delay: .milliseconds(10))
        autosave.start()
        let ids = open(fixture, ["a.com", "b.com"])
        fixture.session.select(ids[0])

        let reader = try database.open()
        let deadline = ContinuousClock.now + .seconds(5)
        while try reader.savedSession().selectedTabID != ids[0], ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        autosave.stop()

        let saved = try reader.savedSession()
        #expect(saved.tabs.map(\.address?.absoluteString) == ["https://a.com", "https://b.com"])
        #expect(saved.selectedTabID == ids[0])
    }

    @Test func aNavigationInsideThePageIsSaved() async throws {
        let database = TemporaryDatabase()
        let fixture = SessionFixture()
        let autosave = SessionAutosave(session: fixture.session, database: try database.open(), delay: .milliseconds(10))
        autosave.start()
        _ = open(fixture, ["a.com"])
        await autosave.saveNow()
        fixture.selectedPage?.followLink(to: URL(string: "https://a.com/clicked")!)

        let reader = try database.open()
        let deadline = ContinuousClock.now + .seconds(5)
        while try reader.savedSession().tabs.first?.address?.absoluteString != "https://a.com/clicked",
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        autosave.stop()

        #expect(try reader.savedSession().tabs.map(\.address?.absoluteString) == ["https://a.com/clicked"])
    }
}
