// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import Testing

@MainActor
@discardableResult
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
private func plain(_ session: ProfileSession) -> [String?] {
    session.tabs.map { $0.address?.host() }
}

@MainActor
@Suite struct PinTests {
    @Test func pinningMovesATabToTheEndOfThePinnedAreaAndKeepsItsPageAndSelection() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        let page = fixture.pages[ids[1]]

        #expect(fixture.session.pin(ids[1]))
        #expect(fixture.session.pin(ids[0]))

        #expect(outline(fixture.session.pinnedItems) == "b.com a.com")
        #expect(plain(fixture.session) == ["c.com"])
        #expect(fixture.session.selectedTabID == ids[2])
        #expect(fixture.pages[ids[1]] === page)
        #expect(page?.isClosed == false)
        #expect(fixture.session.activeSpace.pinnedTabs.map { $0.isPinned } == [true, true])
    }

    @Test func aPinnedTabRemembersTheAddressItWasPinnedAt() {
        let fixture = SessionFixture()
        let id = openTabs(fixture, ["a.com"])[0]
        fixture.pages[id]?.followLink(to: URL(string: "https://a.com/other")!)

        fixture.session.pin(id)
        fixture.pages[id]?.followLink(to: URL(string: "https://a.com/later")!)

        let tab = fixture.session.activeSpace.pinnedTabs[0]
        #expect(tab.pinnedAddress?.absoluteString == "https://a.com/other")
        #expect(tab.address?.absoluteString == "https://a.com/later")
    }

    @Test func unpinningTurnsItBackIntoThePlainTabAtTheTopOfTheOtherTabs() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        fixture.session.pin(ids[2])
        let folder = fixture.session.createFolder(name: "Docs")!
        fixture.session.movePinned(.tab(ids[2]), into: folder)

        #expect(fixture.session.unpin(ids[2]))

        #expect(outline(fixture.session.pinnedItems) == "[Docs: ]")
        #expect(plain(fixture.session) == ["c.com", "a.com", "b.com"])
        let tab = fixture.session.tabs[0]
        #expect(!tab.isPinned)
        #expect(tab.pinnedAddress == nil)
    }

    @Test func pinAndUnpinRefuseWhatIsNotTheRightKindOfTab() {
        let fixture = SessionFixture()
        let id = openTabs(fixture, ["a.com"])[0]

        #expect(!fixture.session.unpin(id))
        #expect(!fixture.session.pin(TabID()))
        fixture.session.pin(id)
        #expect(!fixture.session.pin(id))
        #expect(outline(fixture.session.pinnedItems) == "a.com")
    }

    @Test func togglingPinsThenUnpinsTheSelectedTab() {
        let fixture = SessionFixture()
        openTabs(fixture, ["a.com", "b.com"])

        fixture.session.toggleSelectedTabPin()
        #expect(outline(fixture.session.pinnedItems) == "b.com")
        #expect(plain(fixture.session) == ["a.com"])

        fixture.session.toggleSelectedTabPin()
        #expect(outline(fixture.session.pinnedItems) == "")
        #expect(plain(fixture.session) == ["b.com", "a.com"])
    }

    @Test func thereIsNoPinnedAreaSharedAcrossSpaces() {
        let fixture = SessionFixture()
        let home = fixture.session.activeSpaceID
        let id = openTabs(fixture, ["a.com"])[0]
        fixture.session.pin(id)
        fixture.session.createFolder(name: "Docs")

        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")

        #expect(fixture.session.activeSpaceID == reading)
        #expect(outline(fixture.session.pinnedItems) == "")
        let other = openTabs(fixture, ["b.com"])[0]
        fixture.session.pin(other)
        #expect(outline(fixture.session.pinnedItems) == "b.com")
        fixture.session.selectSpace(home)
        #expect(outline(fixture.session.pinnedItems) == "a.com [Docs: ]")
    }

    @Test func aPinnedTabCannotBeMovedToAnotherSpacesFolder() {
        let fixture = SessionFixture()
        let id = openTabs(fixture, ["a.com"])[0]
        fixture.session.pin(id)
        fixture.session.createSpace(name: "Reading", emoji: "📚")
        let foreign = fixture.session.createFolder(name: "Docs")!

        #expect(!fixture.session.movePinned(.tab(id), into: foreign))
        #expect(outline(fixture.session.spaces[0].pinned) == "a.com")
    }

    @Test func nextAndPreviousTabWalkThePinnedAreaThenTheOtherTabs() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        fixture.session.pin(ids[2])
        let folder = fixture.session.createFolder(name: "Docs")!
        fixture.session.pin(ids[0])
        fixture.session.movePinned(.tab(ids[0]), into: folder)

        fixture.session.select(ids[2])
        var visited: [String?] = []
        for _ in 0..<4 {
            fixture.session.selectTab(offset: 1)
            visited.append(fixture.session.selectedTab?.address?.host())
        }
        #expect(visited == ["a.com", "b.com", "c.com", "a.com"])
        fixture.session.selectTab(offset: -1)
        #expect(fixture.session.selectedTab?.address?.host() == "c.com")
    }

    @Test func nextAndPreviousTabSkipTabsHiddenInACollapsedFolder() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com", "d.com", "e.com"])
        ids.prefix(4).forEach { fixture.session.pin($0) }
        let docs = fixture.session.createFolder(name: "Docs")!
        let notes = fixture.session.createFolder(name: "Notes", in: docs)!
        fixture.session.movePinned(.tab(ids[1]), into: docs)
        fixture.session.movePinned(.tab(ids[2]), into: notes)
        // The pinned area is: a.com, d.com, [Docs: [Notes: c.com], b.com]; then the plain e.com.
        #expect(outline(fixture.session.pinnedItems) == "a.com d.com [Docs: [Notes: c.com] b.com]")
        fixture.session.setFolderExpanded(notes, false)

        fixture.session.select(ids[3])
        fixture.session.selectTab(offset: 1)
        #expect(fixture.session.selectedTab?.address?.host() == "b.com")
        fixture.session.selectTab(offset: -1)
        #expect(fixture.session.selectedTab?.address?.host() == "d.com")

        fixture.session.setFolderExpanded(docs, false)
        fixture.session.selectTab(offset: 1)
        #expect(fixture.session.selectedTab?.address?.host() == "e.com")
        fixture.session.selectTab(offset: -1)
        #expect(fixture.session.selectedTab?.address?.host() == "d.com")

        fixture.session.setFolderExpanded(docs, true)
        fixture.session.setFolderExpanded(notes, true)
        fixture.session.selectTab(offset: 1)
        #expect(fixture.session.selectedTab?.address?.host() == "c.com")
    }

    @Test func nextAndPreviousTabLeaveATabHiddenInACollapsedFolderForTheNextShownOne() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        ids.prefix(2).forEach { fixture.session.pin($0) }
        let docs = fixture.session.createFolder(name: "Docs")!
        fixture.session.movePinned(.tab(ids[0]), into: docs)
        #expect(outline(fixture.session.pinnedItems) == "b.com [Docs: a.com]")
        fixture.session.select(ids[0])
        fixture.session.setFolderExpanded(docs, false)

        fixture.session.selectTab(offset: 1)
        #expect(fixture.session.selectedTab?.address?.host() == "c.com")

        fixture.session.select(ids[0])
        fixture.session.selectTab(offset: -1)
        #expect(fixture.session.selectedTab?.address?.host() == "b.com")
    }

    @Test func nextTabStaysPutWhenEveryTabIsHidden() {
        let fixture = SessionFixture()
        let id = openTabs(fixture, ["a.com"])[0]
        fixture.session.pin(id)
        let docs = fixture.session.createFolder(name: "Docs")!
        fixture.session.movePinned(.tab(id), into: docs)
        fixture.session.setFolderExpanded(docs, false)

        fixture.session.selectTab(offset: 1)

        #expect(fixture.session.selectedTabID == id)
    }

    @Test func aLinkOpenedFromAPinnedTabGoesRightBelowThePinnedArea() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com"])
        fixture.session.pin(ids[0])

        fixture.pages[ids[0]]?.commandClickLink(to: URL(string: "https://new.com")!)

        #expect(plain(fixture.session) == ["new.com", "b.com"])
        #expect(fixture.session.selectedTabID == ids[1])
    }
}

@MainActor
@Suite struct FolderTests {
    @Test func aNewFolderIsEmptyExpandedAndComesLastInThePinnedArea() {
        let fixture = SessionFixture()
        let id = openTabs(fixture, ["a.com"])[0]
        fixture.session.pin(id)

        let folder = fixture.session.createFolder(name: "  Docs ")

        #expect(outline(fixture.session.pinnedItems) == "a.com [Docs: ]")
        #expect(fixture.session.activeSpace.folder(folder!)?.isExpanded == true)
        #expect(fixture.session.activeSpace.folders.map(\.name) == ["Docs"])
        let blank = fixture.session.createFolder(name: "   ")
        #expect(fixture.session.activeSpace.folders.last?.id == blank)
        #expect(fixture.session.activeSpace.folders.last?.name == "New Folder")
    }

    @Test func aFolderAcceptsPinnedTabsAndSubFolders() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com"])
        ids.forEach { fixture.session.pin($0) }
        let docs = fixture.session.createFolder(name: "Docs")!
        let notes = fixture.session.createFolder(name: "Notes")!

        #expect(fixture.session.movePinned(.tab(ids[0]), into: docs))
        #expect(fixture.session.movePinned(.folder(notes), into: docs))
        #expect(fixture.session.movePinned(.tab(ids[1]), into: notes))

        #expect(outline(fixture.session.pinnedItems) == "[Docs: a.com [Notes: b.com]]")
    }

    @Test func aFolderRefusesAPlainTabAndNothingMoves() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com"])
        fixture.session.pin(ids[0])
        let docs = fixture.session.createFolder(name: "Docs")!

        #expect(!fixture.session.movePinned(.tab(ids[1]), into: docs))
        #expect(!fixture.session.movePinned(.tab(ids[1]), into: nil))

        #expect(outline(fixture.session.pinnedItems) == "a.com [Docs: ]")
        #expect(plain(fixture.session) == ["b.com"])
    }

    @Test func aFolderCannotEnterItselfOrOneOfItsOwnSubFolders() {
        let fixture = SessionFixture()
        let docs = fixture.session.createFolder(name: "Docs")!
        let notes = fixture.session.createFolder(name: "Notes", in: docs)!

        #expect(!fixture.session.movePinned(.folder(docs), into: docs))
        #expect(!fixture.session.movePinned(.folder(docs), into: notes))
        #expect(outline(fixture.session.pinnedItems) == "[Docs: [Notes: ]]")
    }

    @Test func pinnedItemsReorderInsideAndAcrossFolders() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        ids.forEach { fixture.session.pin($0) }
        let docs = fixture.session.createFolder(name: "Docs")!

        fixture.session.movePinned(.tab(ids[2]), into: nil, at: 0)
        #expect(outline(fixture.session.pinnedItems) == "c.com a.com b.com [Docs: ]")

        fixture.session.movePinned(.tab(ids[0]), into: docs)
        fixture.session.movePinned(.tab(ids[1]), into: docs, at: 0)
        #expect(outline(fixture.session.pinnedItems) == "c.com [Docs: b.com a.com]")

        fixture.session.movePinned(.folder(docs), into: nil, at: 0)
        #expect(outline(fixture.session.pinnedItems) == "[Docs: b.com a.com] c.com")

        fixture.session.movePinned(.tab(ids[1]), into: docs, at: 99)
        #expect(outline(fixture.session.pinnedItems) == "[Docs: a.com b.com] c.com")
    }

    @Test func aPinnedItemCanBeDroppedBeforeAnotherPinnedItem() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        ids.forEach { fixture.session.pin($0) }
        let docs = fixture.session.createFolder(name: "Docs")!
        fixture.session.movePinned(.tab(ids[1]), into: docs)

        #expect(fixture.session.movePinned(.tab(ids[2]), before: .tab(ids[0])))
        #expect(outline(fixture.session.pinnedItems) == "c.com a.com [Docs: b.com]")
        #expect(fixture.session.movePinned(.tab(ids[0]), before: .tab(ids[1])))
        #expect(outline(fixture.session.pinnedItems) == "c.com [Docs: a.com b.com]")
        #expect(!fixture.session.movePinned(.tab(ids[0]), before: .tab(ids[0])))
        #expect(!fixture.session.movePinned(.folder(docs), before: .tab(ids[1])))
        #expect(outline(fixture.session.pinnedItems) == "c.com [Docs: a.com b.com]")
    }

    @Test func moveUpAndDownReorderAPinnedTabAmongItsSiblings() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        ids.forEach { fixture.session.pin($0) }

        #expect(fixture.session.canMove(ids[0], by: 1))
        #expect(!fixture.session.canMove(ids[0], by: -1))
        fixture.session.move(ids[0], by: 1)
        #expect(outline(fixture.session.pinnedItems) == "b.com a.com c.com")
        fixture.session.move(ids[2], by: -2)
        #expect(outline(fixture.session.pinnedItems) == "c.com b.com a.com")
        #expect(!fixture.session.canMove(ids[2], by: -1))
    }

    @Test func moveUpAndDownCountOnlyTheTabsAndNeverStopOnAFolderAmongThem() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        ids.forEach { fixture.session.pin($0) }
        let docs = fixture.session.createFolder(name: "F")!
        fixture.session.movePinned(.folder(docs), into: nil, at: 1)
        #expect(outline(fixture.session.pinnedItems) == "a.com [F: ] b.com c.com")

        fixture.session.move(ids[2], by: -1)
        #expect(outline(fixture.session.pinnedItems) == "a.com [F: ] c.com b.com")

        fixture.session.move(ids[0], by: 1)
        #expect(outline(fixture.session.pinnedItems) == "[F: ] c.com a.com b.com")

        fixture.session.move(ids[0], by: 5)
        #expect(outline(fixture.session.pinnedItems) == "[F: ] c.com b.com a.com")
        #expect(!fixture.session.canMove(ids[0], by: 1))
        #expect(fixture.session.canMove(ids[0], by: -1))
    }

    @Test func renamingAndCollapsingAFolder() {
        let fixture = SessionFixture()
        let docs = fixture.session.createFolder(name: "Docs")!

        fixture.session.renameFolder(docs, name: " Reading list ")
        fixture.session.renameFolder(docs, name: "  ")
        fixture.session.setFolderExpanded(docs, false)

        let folder = fixture.session.activeSpace.folders[0]
        #expect(folder.name == "Reading list")
        #expect(!folder.isExpanded)
    }

    @Test func deletingAFolderKeepsWhatItHeldInItsPlace() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com", "c.com"])
        ids.forEach { fixture.session.pin($0) }
        let docs = fixture.session.createFolder(name: "Docs")!
        let notes = fixture.session.createFolder(name: "Notes", in: docs)!
        fixture.session.movePinned(.tab(ids[1]), into: docs, at: 0)
        fixture.session.movePinned(.tab(ids[2]), into: notes)
        fixture.session.movePinned(.folder(docs), into: nil, at: 1)
        #expect(outline(fixture.session.pinnedItems) == "a.com [Docs: b.com [Notes: c.com]]")

        fixture.session.deleteFolder(docs)

        #expect(outline(fixture.session.pinnedItems) == "a.com b.com [Notes: c.com]")
    }

    @Test func closingAPinnedTabKeepsItPinnedAndLoadsItAgainWhenShown() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com"])
        fixture.session.pin(ids[0])
        fixture.session.select(ids[0])
        let page = fixture.pages[ids[0]]

        fixture.session.close(ids[0])

        #expect(page?.isClosed == true)
        #expect(outline(fixture.session.pinnedItems) == "a.com")
        #expect(fixture.session.selectedTabID == ids[1])
        #expect(fixture.session.canReopenClosedTab == false)
        fixture.session.select(ids[0])
        #expect(fixture.pages[ids[0]] !== page)
        #expect(fixture.pages[ids[0]]?.isClosed == false)
        #expect(fixture.pages[ids[0]]?.restoreCount == 1)
    }

    @Test func closingTheLastPlainTabSelectsTheLastPinnedTab() {
        let fixture = SessionFixture()
        let ids = openTabs(fixture, ["a.com", "b.com"])
        fixture.session.pin(ids[0])

        fixture.session.close(ids[1])

        #expect(fixture.session.selectedTabID == ids[0])
    }

    @Test func deletingASpaceClosesItsPinnedTabsToo() {
        let fixture = SessionFixture()
        fixture.session.createSpace(name: "Reading", emoji: "📚")
        let id = openTabs(fixture, ["a.com"])[0]
        fixture.session.pin(id)
        let page = fixture.pages[id]

        fixture.session.deleteSpace(fixture.session.activeSpaceID)

        #expect(page?.isClosed == true)
        #expect(fixture.session.spaces.count == 1)
    }
}

@MainActor
private final class Disk {
    let folder = FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)",
                                                                 directoryHint: .isDirectory)
    var file: URL { folder.appending(path: "profile.sqlite") }
    deinit { try? FileManager.default.removeItem(at: folder) }
}

@MainActor
@Suite struct PinnedRelaunchTests {
    @Test func pinnedTabsAndFoldersSurviveARelaunchAndEveryPinnedTabReloads() async throws {
        let disk = Disk()
        let before = SessionFixture()
        let ids = openTabs(before, ["a.com", "b.com", "c.com", "d.com"])
        ids.prefix(3).forEach { before.session.pin($0) }
        let docs = before.session.createFolder(name: "Docs")!
        before.session.movePinned(.tab(ids[1]), into: docs)
        let notes = before.session.createFolder(name: "Notes", in: docs)!
        before.session.movePinned(.tab(ids[2]), into: notes)
        before.session.setFolderExpanded(notes, false)
        before.session.select(ids[3])
        await SessionAutosave(session: before.session, database: try ProfileDatabase(file: disk.file)).saveNow()

        let after = SessionFixture()
        after.session.restore(try ProfileDatabase(file: disk.file).savedSession())

        #expect(outline(after.session.pinnedItems) == "a.com [Docs: b.com [Notes: c.com]]")
        #expect(plain(after.session) == ["d.com"])
        #expect(after.session.activeSpace.folders.map { $0.isExpanded } == [true, false])
        #expect(after.session.activeSpace.pinnedTabs.allSatisfy { $0.isPinned })
        #expect(after.session.selectedTabID == ids[3])
        #expect(Set(after.pages.keys) == Set(ids))
        #expect(after.pages.values.map(\.restoreCount).allSatisfy { $0 == 1 })
    }

    @Test func aRestoredPinnedTabKeepsTheAddressItWasPinnedAt() async throws {
        let disk = Disk()
        let before = SessionFixture()
        let id = openTabs(before, ["a.com"])[0]
        before.session.pin(id)
        before.pages[id]?.followLink(to: URL(string: "https://a.com/deep")!)
        await SessionAutosave(session: before.session, database: try ProfileDatabase(file: disk.file)).saveNow()

        let after = SessionFixture()
        after.session.restore(try ProfileDatabase(file: disk.file).savedSession())

        let tab = try #require(after.session.activeSpace.pinnedTabs.first)
        #expect(tab.pinnedAddress?.absoluteString == "https://a.com")
        #expect(tab.address?.absoluteString == "https://a.com/deep")
    }

    @Test func eachSpaceKeepsItsOwnPinnedAreaAcrossARelaunch() async throws {
        let disk = Disk()
        let before = SessionFixture()
        let homeTab = openTabs(before, ["a.com"])[0]
        before.session.pin(homeTab)
        before.session.createSpace(name: "Reading", emoji: "📚")
        let readingTab = openTabs(before, ["b.com"])[0]
        before.session.pin(readingTab)
        before.session.createFolder(name: "Docs")
        await SessionAutosave(session: before.session, database: try ProfileDatabase(file: disk.file)).saveNow()

        let after = SessionFixture()
        after.session.restore(try ProfileDatabase(file: disk.file).savedSession())

        #expect(after.session.spaces.map { outline($0.pinned) } == ["a.com", "b.com [Docs: ]"])
        #expect(Set(after.pages.keys) == [homeTab, readingTab])
    }

    @Test func pinningIsSavedByTheAutosaveWithoutAnyOtherChange() async throws {
        let disk = Disk()
        let fixture = SessionFixture()
        let id = openTabs(fixture, ["a.com"])[0]
        let autosave = SessionAutosave(session: fixture.session, database: try ProfileDatabase(file: disk.file),
                                       delay: .milliseconds(20), period: .seconds(60))
        autosave.start()
        await autosave.saveNow()

        fixture.session.pin(id)
        fixture.session.createFolder(name: "Docs")
        // Wait for the debounced save itself rather than a fixed delay, which a loaded machine overran.
        let deadline = ContinuousClock.now + .seconds(10)
        var latest: SavedSession?
        while (latest?.spaces.first?.pinned.count ?? 0) < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
            if let next = try? ProfileDatabase(file: disk.file).savedSession() { latest = next }
        }
        autosave.stop()
        let saved = try #require(latest)

        #expect(saved.spaces[0].pinned.count == 2)
        #expect(saved.spaces[0].tabs == [])
    }
}
