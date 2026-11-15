// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

@MainActor
@Suite struct SpaceThemeTests {
    @Test func aNewSpaceTakesTheFirstThemeNoSpaceOfTheProfileUses() throws {
        let fixture = SessionFixture()
        fixture.session.restore(SavedSession(spaces: [
            SpaceRecord(id: SavedSession.onlySpace, name: "Home", icon: .emoji("🏠"), paletteID: "indigo-blue"),
        ], activeSpaceID: SavedSession.onlySpace))

        try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"))
        try fixture.session.createSpace(name: "Music", icon: .emoji("🎵"))

        #expect(fixture.session.spaces.map(\.paletteID) == ["indigo-blue", "orange-pink", "teal-green"])
    }

    @Test func aNewSpaceCanBeGivenAThemeOfThePalette() throws {
        let fixture = SessionFixture()

        try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"), paletteID: "mint-cyan")

        #expect(fixture.session.activeSpace.paletteID == "mint-cyan")
    }

    @Test func aThemeThePaletteDoesNotHaveIsNotKept() throws {
        let fixture = SessionFixture()

        try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"), paletteID: "ocean")

        #expect(fixture.session.activeSpace.paletteID == "indigo-blue")
    }

    @Test func aSpaceChangesThemeWithoutLosingItsNameOrItsTabs() throws {
        let fixture = SessionFixture()
        fixture.session.openCommandBar(for: .newTab)
        fixture.session.submitCommandBar("a.com")
        let home = fixture.session.activeSpaceID

        try fixture.session.editSpace(home, name: "Home", icon: .emoji("🏠"), paletteID: "red-orange")

        #expect(fixture.session.activeSpace.paletteID == "red-orange")
        #expect(fixture.session.activeSpace.name == "Home")
        #expect(fixture.session.tabs.count == 1)
    }

    @Test func renamingWithoutAThemeOrWithAnUnknownOneKeepsTheCurrentTheme() throws {
        let fixture = SessionFixture()
        let home = fixture.session.activeSpaceID
        try fixture.session.editSpace(home, name: "Home", icon: .emoji("🏠"), paletteID: "purple-pink")

        try fixture.session.editSpace(home, name: "Base", icon: .emoji("🏠"))
        try fixture.session.editSpace(home, name: "Base", icon: .emoji("🏠"), paletteID: "ocean")

        #expect(fixture.session.activeSpace.paletteID == "purple-pink")
        #expect(fixture.session.activeSpace.name == "Base")
    }

    @Test func eachSpaceKeepsItsOwnThemeInTheSavedSessionAndAfterARestore() throws {
        let fixture = SessionFixture()
        let home = fixture.session.activeSpaceID
        try fixture.session.editSpace(home, name: "Home", icon: .emoji("🏠"), paletteID: "brown-yellow")
        try fixture.session.createSpace(name: "Reading", icon: .emoji("📚"), paletteID: "teal-green")

        let saved = fixture.session.savedSession()
        #expect(saved.spaces.map(\.paletteID) == ["brown-yellow", "teal-green"])

        let relaunched = SessionFixture()
        relaunched.session.restore(saved)
        #expect(relaunched.session.spaces.map(\.paletteID) == ["brown-yellow", "teal-green"])
    }
}
