// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

private let workID = ProfileID(rawValue: UUID(uuidString: "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A")!)
private let personalID = ProfileID(rawValue: UUID(uuidString: "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F")!)

@MainActor
private func open(_ address: String, in fixture: SessionFixture) -> TabID {
    fixture.session.openCommandBar(for: .newTab)
    fixture.session.submitCommandBar(address)
    return fixture.session.selectedTabID!
}

/// What stays inside one Profile at the session level, without WebKit (docs/architecture-v1.md §9.2, point 6).
@MainActor
@Suite struct ProfileIsolationTests {
    @Test func aTabMovesToAnotherSpaceOfItsProfileWithItsPage() {
        let fixture = SessionFixture(id: workID)
        let home = fixture.session.activeSpaceID
        let tab = open("https://a.com", in: fixture)
        let page = fixture.selectedPage
        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")

        #expect(fixture.session.move(tab, toSpace: reading))

        #expect(fixture.session.spaces.first { $0.id == home }?.tabs.isEmpty == true)
        #expect(fixture.session.spaces.first { $0.id == reading }?.tabs.map(\.id) == [tab])
        #expect(page?.isClosed == false)
        #expect(fixture.pages[tab] === page)
    }

    @Test func movingATabToASpaceOfAnotherProfileIsRefused() {
        let work = SessionFixture(id: workID)
        let personal = SessionFixture(id: personalID)
        let tab = open("https://a.com", in: work)
        let personalSpace = personal.session.activeSpaceID

        #expect(!work.session.move(tab, toSpace: personalSpace))

        #expect(work.addresses == ["https://a.com"])
        #expect(work.session.selectedTabID == tab)
        #expect(personal.session.tabs.isEmpty)
        #expect(personal.session.move(tab, toSpace: personalSpace) == false)
    }

    @Test func theCommandBarOfOneProfileOpensNothingInAnother() {
        let work = SessionFixture(searchEngine: .kagi, id: workID)
        let personal = SessionFixture(searchEngine: .duckDuckGo, id: personalID)

        work.session.openCommandBar(for: .newTab)
        work.session.submitCommandBar("quarterly report")
        _ = open("https://intranet.example", in: work)

        #expect(work.addresses == ["https://kagi.com/search?q=quarterly%20report", "https://intranet.example"])
        #expect(personal.addresses == [])
        #expect(personal.createdPageCount == 0)
    }

    @Test func choosingASearchEngineInOneProfileLeavesAnotherWithout() {
        let work = SessionFixture(id: workID)
        let personal = SessionFixture(id: personalID)
        work.session.submitCommandBar("weather")
        #expect(work.session.searchAwaitingEngine == "weather")

        work.session.chooseSearchEngine(.ecosia)

        #expect(work.session.settings.searchEngine == .ecosia)
        #expect(personal.session.settings.searchEngine == nil)
        personal.session.submitCommandBar("weather")
        #expect(personal.session.searchAwaitingEngine == "weather")
        #expect(personal.addresses == [])
    }

    @Test func webContentSettingsBelongToOneProfile() {
        let work = SessionFixture(id: workID)
        let personal = SessionFixture(id: personalID)

        work.session.setWebContentSettings(WebContentSettings(isFraudulentSiteWarningEnabled: false,
                                                              isAutoplayingSoundAllowed: true))

        #expect(work.session.settings.webContent == WebContentSettings(isFraudulentSiteWarningEnabled: false,
                                                                       isAutoplayingSoundAllowed: true))
        #expect(personal.session.settings.webContent == WebContentSettings())
    }

    @Test func closingEveryTabOfADeletedProfileClosesEveryPageForGood() {
        let fixture = SessionFixture(id: workID)
        _ = open("https://a.com", in: fixture)
        fixture.session.createSpace(name: "Reading", emoji: "📚")
        _ = open("https://b.com", in: fixture)

        fixture.session.closeAllTabs()

        #expect(fixture.pages.values.allSatisfy { $0.isClosed })
        #expect(fixture.session.spaces.allSatisfy { $0.tabs.isEmpty })
        #expect(!fixture.session.canReopenClosedTab)
    }

    @Test func aChosenSearchEngineIsSavedWithTheProfileShortlyAfterwards() async throws {
        let database = TemporaryDatabase()
        let fixture = SessionFixture(id: workID)
        let connection = try database.open()
        let autosave = SessionAutosave(session: fixture.session, database: connection, delay: .milliseconds(10))
        autosave.start()
        await autosave.saveNow()

        fixture.session.submitCommandBar("weather")
        fixture.session.chooseSearchEngine(.braveSearch)

        let deadline = ContinuousClock.now + .seconds(5)
        while (try connection.settings().searchEngine) == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        autosave.stop()
        #expect(try connection.settings().searchEngine == .braveSearch)
    }
}
