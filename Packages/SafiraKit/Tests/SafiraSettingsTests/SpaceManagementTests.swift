// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppShellKit
import Foundation
import SafiraCore
import SafiraSession
import SafiraSettings
import Spaces
import Testing

private let profile = ProfileID(rawValue: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
private let home = SpaceID(rawValue: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!)
private let reading = SpaceID(rawValue: UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!)
private let work = SpaceID(rawValue: UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!)

/// A Profile with Home (shown, no Tab), Reading (two Tabs) and Work (no Tab). Only the shown Space's selected Tab gets a
/// page, so no page is ever made here.
@MainActor
private func threeSpaces() -> ProfileSession {
    let session = ProfileSession(profileID: profile) { _ in fatalError("no page is needed") }
    session.restore(SavedSession(spaces: [
        SpaceRecord(id: home, name: "Home", icon: .emoji("🏠"), paletteID: "indigo-blue"),
        SpaceRecord(id: reading, name: "Reading", icon: .symbol("book"), paletteID: "teal-green", tabs: [
            TabRecord(id: TabID(), address: URL(string: "https://a.com/")),
            TabRecord(id: TabID(), address: URL(string: "https://b.com/")),
        ]),
        SpaceRecord(id: work, name: "Work", icon: .initial, paletteID: "red-orange"),
    ], activeSpaceID: home))
    return session
}

@MainActor
private func oneSpace() -> ProfileSession {
    ProfileSession(profileID: profile) { _ in fatalError("no page is needed") }
}

@MainActor
@Suite struct SpaceManagementTests {
    @Test func theKitsEditorCreatesASpaceWithASymbolShownAtOnceInAThemeNoOtherSpaceWears() throws {
        let session = oneSpace()
        let model = SpaceManagement.editorForNewSpace(in: session)
        #expect(model.purpose == .create)
        #expect(model.draft.name == "Space 2")
        #expect(model.draft.icon == .initial)
        #expect(model.draft.themeID != session.spaces[0].paletteID)

        model.draft.name = "  Work "
        model.iconSelection = .symbol("briefcase")
        let draft = try #require(model.save())
        let created = try #require(SpaceManagement.apply(.saved(draft), editing: nil, in: session))

        #expect(session.spaces.map(\.name) == ["Home", "Work"])
        #expect(session.spaces.map(\.icon) == [.emoji("🏠"), .symbol("briefcase")])
        #expect(session.spaces[1].paletteID == model.draft.themeID)
        #expect(session.activeSpaceID == created)
    }

    @Test func theKitsEditorTakesAnEmojiOrTheInitialOfTheName() throws {
        let session = oneSpace()
        let emoji = SpaceManagement.editorForNewSpace(in: session)
        emoji.draft.name = "Art"
        emoji.iconSelection = .emoji
        #expect(emoji.enterEmoji("paint 🎨"))
        SpaceManagement.apply(.saved(try #require(emoji.save())), editing: nil, in: session)

        let initial = SpaceManagement.editorForNewSpace(in: session)
        #expect(initial.draft.name == "Space 3")
        SpaceManagement.apply(.saved(try #require(initial.save())), editing: nil, in: session)

        #expect(session.spaces.map(\.icon) == [.emoji("🏠"), .emoji("🎨"), .initial])
        #expect(SpaceMark(session.spaces[2].icon, name: session.spaces[2].name) == .text("S"))
    }

    @Test func aProposedNameAnotherSpaceAlreadyHasIsSkipped() throws {
        let session = oneSpace()
        try session.createSpace(name: "space 2")
        #expect(SpaceManagement.editorForNewSpace(in: session).draft.name == "Space 3")
    }

    @Test func theKitsEditorEditsASpaceAndOffersDeleteOnlyWhenTheProfileHasAnother() throws {
        let session = threeSpaces()
        let model = try #require(SpaceManagement.editor(editing: reading, in: session))
        #expect(model.purpose == .edit)
        #expect(model.draft == SpaceDraft(name: "Reading", icon: .symbol("book"), themeID: "teal-green"))
        #expect(model.canDelete)
        #expect(model.otherNames == ["Home", "Work"])

        model.draft.name = "Research"
        model.iconSelection = .initial
        model.draft.themeID = "mint-cyan"
        let draft = try #require(model.save())
        #expect(SpaceManagement.apply(.saved(draft), editing: reading, in: session) == reading)

        #expect(session.spaces.map(\.name) == ["Home", "Research", "Work"])
        #expect(session.spaces[1].icon == .initial)
        #expect(session.spaces[1].paletteID == "mint-cyan")
        #expect(session.activeSpaceID == home)
        #expect(SpaceManagement.editor(editing: session.spaces[0].id, in: oneSpace()) == nil)
        let only = oneSpace()
        #expect(try #require(SpaceManagement.editor(editing: only.spaces[0].id, in: only)).canDelete == false)
    }

    @Test func theKitsEditorRefusesANameAnotherSpaceHasAndSavingItAnywayChangesNothing() throws {
        let session = threeSpaces()
        let model = try #require(SpaceManagement.editor(editing: work, in: session))
        model.draft.name = " home "
        #expect(!model.canSave)
        #expect(model.nameMessage == "A space named “home” already exists.")
        #expect(model.save() == nil)

        let refused = SpaceDraft(name: "READING", icon: .emoji("📚"), themeID: "ocean")
        #expect(SpaceManagement.apply(.saved(refused), editing: work, in: session) == nil)
        #expect(SpaceManagement.apply(.saved(refused), editing: nil, in: session) == nil)
        #expect(session.spaces.map(\.name) == ["Home", "Reading", "Work"])
        #expect(session.spaces[2].icon == .initial)
    }

    @Test func aCancelOrADeleteRequestFromTheEditorChangesNothing() throws {
        let session = threeSpaces()
        #expect(SpaceManagement.apply(.cancelled, editing: nil, in: session) == nil)
        #expect(SpaceManagement.apply(.deleteRequested, editing: reading, in: session) == nil)
        #expect(session.spaces.map(\.id) == [home, reading, work])
    }

    @Test func deletingAsksWithTheKitsConfirmationWhichSaysTheTabsCloseAndNothingMoves() throws {
        let session = threeSpaces()

        let deletion = try #require(SpaceManagement.deletion(of: reading, in: session))
        #expect(deletion.title == "Delete the Space “Reading”?")
        #expect(deletion.messageText == "Its 2 Tabs will close. The Profile's logins and history are kept.")
        #expect(deletion.choices == .deleteEmpty)
        #expect(SpaceManagement.deletion(of: work, in: session)?.messageText
            == "It has no Tab. The Profile's logins and history are kept.")

        SpaceManagement.perform(.delete(reading, movingContentTo: nil), in: session) { _ in Issue.record("no editor") }

        #expect(session.spaces.map(\.id) == [home, work])
        #expect(session.spaces.flatMap(\.allTabs).isEmpty)
    }

    @Test func theProfilesLastSpaceHasNoDeletion() {
        let session = oneSpace()
        #expect(SpaceManagement.deletion(of: session.spaces[0].id, in: session) == nil)
        #expect(SpaceManagement.deletion(of: SpaceID(), in: threeSpaces()) == nil)
    }

    @Test func aDragInTheKitsListChangesTheOrderOfControlOneToNine() throws {
        let session = threeSpaces()
        let order = try SpaceRules.moved(SpaceManagement.items(of: session).map(\.id), fromOffsets: [2], toOffset: 0)

        SpaceManagement.perform(.reorder(order), in: session) { _ in Issue.record("no editor") }

        #expect(session.spaces.map(\.name) == ["Work", "Home", "Reading"])
        #expect(SpaceManagement.items(of: session).map(\.name) == ["Work", "Home", "Reading"])
        session.selectSpace(number: 1)
        #expect(session.activeSpaceID == work)
        session.selectSpace(number: 2)
        #expect(session.activeSpaceID == home)
    }

    @Test func theListsNewAndEditOpenTheEditor() {
        let session = threeSpaces()
        var opened: [SpaceID?] = []
        SpaceManagement.perform(.create, in: session) { opened.append($0) }
        SpaceManagement.perform(.edit(work), in: session) { opened.append($0) }
        #expect(opened == [nil, work])
    }

    @Test func theListShowsEachSpacesIconThemeTabsAndWhichOneIsShown() {
        let items = SpaceManagement.items(of: threeSpaces())
        #expect(items.map(\.icon) == [.emoji("🏠"), .symbol("book"), .initial])
        #expect(items.map(\.themeID) == ["indigo-blue", "teal-green", "red-orange"])
        #expect(items.map(\.detail) == ["0 Tabs", "2 Tabs", "0 Tabs"])
        #expect(items.map(\.note) == ["Shown", nil, nil])
    }
}
