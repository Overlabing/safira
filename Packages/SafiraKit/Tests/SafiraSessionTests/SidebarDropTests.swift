// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import Testing

@MainActor
private func openTabs(_ fixture: SessionFixture, _ addresses: [String]) -> [TabID] {
    addresses.map { address in
        fixture.session.openCommandBar(for: .newTab)
        fixture.session.submitCommandBar(address)
        return fixture.session.selectedTabID!
    }
}

/// The pinned area as plain text: a Pinned tab by its host, a Folder as `[name: …]`.
@MainActor
private func outline(_ items: [PinnedItem]) -> String {
    items.map { item -> String in
        switch item {
        case .tab(let tab): tab.address?.host() ?? "blank"
        case .folder(let folder): "[\(folder.name): \(outline(folder.items))]"
        }
    }.joined(separator: " ")
}

@MainActor
private func plain(_ session: ProfileSession) -> String {
    session.tabs.map { $0.address?.host() ?? "blank" }.joined(separator: " ")
}

@MainActor
@Suite struct SidebarDropTests {
    @Test func aPlainTabDroppedInThePinnedAreaIsPinnedAtThatPlaceAtTheAddressItShows() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        fixture.session.pin(ids[0])
        fixture.pages[ids[2]]?.followLink(to: URL(string: "https://c.com/inbox")!)

        #expect(fixture.session.drop(.tab(ids[2]), at: .pinned(folder: nil, index: 0)))

        #expect(outline(fixture.session.pinnedItems) == "c.com a.com")
        #expect(plain(fixture.session) == "b.com")
        let tab = fixture.session.activeSpace.pinnedTabs[0]
        #expect(tab.isPinned)
        #expect(tab.pinnedAddress?.absoluteString == "https://c.com/inbox")
    }

    @Test func droppingNeverSelectsNorLoadsTheDraggedTab() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        fixture.session.select(ids[0])
        let page = fixture.pages[ids[2]]
        let loads = page?.loadCount

        fixture.session.drop(.tab(ids[2]), at: .pinned(folder: nil, index: 0))
        fixture.session.drop(.tab(ids[2]), at: .tabs(index: 0))

        #expect(fixture.session.selectedTabID == ids[0])
        #expect(fixture.pages[ids[2]] === page)
        #expect(page?.loadCount == loads)
        #expect(page?.isClosed == false)
    }

    @Test func aPlainTabDroppedIntoAFolderIsPinnedInsideIt() throws {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        fixture.session.pin(ids[0])
        let docs = try #require(fixture.session.createFolder(name: "Docs"))
        fixture.session.movePinned(.tab(ids[0]), into: docs)

        #expect(fixture.session.drop(.tab(ids[1]), at: .pinned(folder: docs, index: 1)))
        #expect(fixture.session.drop(.tab(ids[2]), at: .pinned(folder: docs, index: 0)))

        #expect(outline(fixture.session.pinnedItems) == "[Docs: c.com a.com b.com]")
        #expect(plain(fixture.session) == "")
    }

    @Test func aPinnedTabDroppedAmongTheOtherTabsBecomesAPlainTabAtThatPlace() throws {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com", "d.com"])
        fixture.session.pin(ids[0])
        fixture.session.pin(ids[1])
        let docs = try #require(fixture.session.createFolder(name: "Docs"))
        fixture.session.movePinned(.tab(ids[1]), into: docs)

        #expect(fixture.session.drop(.tab(ids[0]), at: .tabs(index: 1)))
        #expect(fixture.session.drop(.tab(ids[1]), at: .tabs(index: 3)))

        #expect(outline(fixture.session.pinnedItems) == "[Docs: ]")
        #expect(plain(fixture.session) == "c.com a.com d.com b.com")
        #expect(fixture.session.tabs.allSatisfy { !$0.isPinned && $0.pinnedAddress == nil })
    }

    @Test func plainTabsReorderAmongThemselvesByTheGapTheyAreDroppedIn() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com", "d.com"])

        #expect(fixture.session.drop(.tab(ids[0]), at: .tabs(index: 3)))
        #expect(plain(fixture.session) == "b.com c.com a.com d.com")
        #expect(fixture.session.drop(.tab(ids[3]), at: .tabs(index: 0)))
        #expect(plain(fixture.session) == "d.com b.com c.com a.com")
        #expect(fixture.session.drop(.tab(ids[1]), at: .tabs(index: 4)))
        #expect(plain(fixture.session) == "d.com c.com a.com b.com")
        #expect(fixture.session.drop(.tab(ids[2]), at: .tabs(index: 2)))
        #expect(plain(fixture.session) == "d.com c.com a.com b.com")
    }

    @Test func pinnedItemsReorderInTheirAreaAndMoveBetweenFolders() throws {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        ids.forEach { fixture.session.pin($0) }
        let docs = try #require(fixture.session.createFolder(name: "Docs"))

        #expect(fixture.session.drop(.tab(ids[0]), at: .pinned(folder: nil, index: 3)))
        #expect(outline(fixture.session.pinnedItems) == "b.com c.com a.com [Docs: ]")
        #expect(fixture.session.drop(.folder(docs), at: .pinned(folder: nil, index: 0)))
        #expect(outline(fixture.session.pinnedItems) == "[Docs: ] b.com c.com a.com")
        #expect(fixture.session.drop(.tab(ids[2]), at: .pinned(folder: docs, index: 0)))
        #expect(fixture.session.drop(.tab(ids[0]), at: .pinned(folder: docs, index: 0)))
        #expect(outline(fixture.session.pinnedItems) == "[Docs: a.com c.com] b.com")
        #expect(fixture.session.drop(.tab(ids[2]), at: .pinned(folder: docs, index: 0)))
        #expect(outline(fixture.session.pinnedItems) == "[Docs: c.com a.com] b.com")
        #expect(fixture.session.drop(.tab(ids[2]), at: .pinned(folder: nil, index: 2)))
        #expect(outline(fixture.session.pinnedItems) == "[Docs: a.com] b.com c.com")
    }

    @Test func emptyAreasAcceptADrop() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com"])

        #expect(fixture.session.drop(.tab(ids[0]), at: .pinned(folder: nil, index: 0)))
        #expect(outline(fixture.session.pinnedItems) == "a.com")
        #expect(plain(fixture.session) == "")

        #expect(fixture.session.drop(.tab(ids[0]), at: .tabs(index: 0)))
        #expect(outline(fixture.session.pinnedItems) == "")
        #expect(plain(fixture.session) == "a.com")
    }

    @Test func refusedDropsMoveNothing() throws {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com"])
        fixture.session.pin(ids[0])
        let docs = try #require(fixture.session.createFolder(name: "Docs"))
        let notes = try #require(fixture.session.createFolder(name: "Notes", in: docs))

        #expect(!fixture.session.drop(.folder(docs), at: .tabs(index: 0)))
        #expect(!fixture.session.drop(.folder(docs), at: .pinned(folder: notes, index: 0)))
        #expect(!fixture.session.drop(.folder(docs), at: .pinned(folder: docs, index: 0)))
        #expect(!fixture.session.drop(.tab(ids[1]), at: .pinned(folder: FolderID(), index: 0)))
        #expect(!fixture.session.drop(.tab(TabID()), at: .tabs(index: 0)))

        #expect(outline(fixture.session.pinnedItems) == "a.com [Docs: [Notes: ]]")
        #expect(plain(fixture.session) == "b.com")
    }

    @Test func aTabOfAnotherSpaceIsNotDroppedInTheActiveOne() throws {
        let fixture = SessionFixture()
        let home = openTabs(fixture, ["a.com"])[0]
        try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))
        openTabs(fixture, ["b.com"])

        #expect(!fixture.session.drop(.tab(home), at: .pinned(folder: nil, index: 0)))
        #expect(!fixture.session.drop(.tab(home), at: .tabs(index: 0)))

        #expect(outline(fixture.session.pinnedItems) == "")
        #expect(plain(fixture.session) == "b.com")
        #expect(fixture.session.spaces.map { $0.tabs.count } == [1, 1])
    }
}

@MainActor
@Suite struct SidebarDropRelaunchTests {
    @Test func droppedTabsKeepTheirPlaceAcrossARelaunchInEverySpace() async throws {
        let disk = Disk()
        let before = SessionFixture()
        let home = openTabs(before, ["a.com", "b.com", "c.com"])
        before.session.drop(.tab(home[2]), at: .pinned(folder: nil, index: 0))
        before.session.drop(.tab(home[1]), at: .tabs(index: 0))
        try before.session.createSpace(name: "Reading", icon: .emoji("📚"))
        let reading = openTabs(before, ["d.com", "e.com"])
        let docs = try #require(before.session.createFolder(name: "Docs"))
        before.session.drop(.tab(reading[1]), at: .pinned(folder: docs, index: 0))
        await SessionAutosave(session: before.session, database: try ProfileDatabase(file: disk.file)).saveNow()

        let after = SessionFixture()
        after.session.restore(try ProfileDatabase(file: disk.file).savedSession())

        #expect(after.session.spaces.map { outline($0.pinned) } == ["c.com", "[Docs: e.com]"])
        #expect(after.session.spaces.map { $0.tabs.map { $0.address?.host() ?? "" } } == [["b.com", "a.com"], ["d.com"]])
        #expect(after.session.spaces.flatMap(\.pinnedTabs).allSatisfy { $0.isPinned })
    }
}
