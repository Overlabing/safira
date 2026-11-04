// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

@MainActor
@Suite struct SpaceThemeTests {
    @Test func aNewSpaceTakesTheFirstThemeNoSpaceOfTheProfileUses() {
        let fixture = SessionFixture()
        fixture.session.restore(SavedSession(spaces: [
            SpaceRecord(id: SavedSession.onlySpace, name: "Home", emoji: "🏠", paletteID: "indigo-blue"),
        ], activeSpaceID: SavedSession.onlySpace))

        fixture.session.createSpace(name: "Reading", emoji: "📚")
        fixture.session.createSpace(name: "Music", emoji: "🎵")

        #expect(fixture.session.spaces.map(\.paletteID) == ["indigo-blue", "orange-pink", "teal-green"])
    }

    @Test func aNewSpaceCanBeGivenAThemeOfThePalette() {
        let fixture = SessionFixture()

        fixture.session.createSpace(name: "Reading", emoji: "📚", paletteID: "mint-cyan")

        #expect(fixture.session.activeSpace.paletteID == "mint-cyan")
    }

    @Test func aThemeThePaletteDoesNotHaveIsNotKept() {
        let fixture = SessionFixture()

        fixture.session.createSpace(name: "Reading", emoji: "📚", paletteID: "ocean")

        #expect(fixture.session.activeSpace.paletteID == "indigo-blue")
    }

    @Test func aSpaceChangesThemeWithoutLosingItsNameOrItsTabs() {
        let fixture = SessionFixture()
        fixture.session.openCommandBar(for: .newTab)
        fixture.session.submitCommandBar("a.com")
        let home = fixture.session.activeSpaceID

        fixture.session.renameSpace(home, name: "Home", emoji: "🏠", paletteID: "red-orange")

        #expect(fixture.session.activeSpace.paletteID == "red-orange")
        #expect(fixture.session.activeSpace.name == "Home")
        #expect(fixture.session.tabs.count == 1)
    }

    @Test func renamingWithoutAThemeOrWithAnUnknownOneKeepsTheCurrentTheme() {
        let fixture = SessionFixture()
        let home = fixture.session.activeSpaceID
        fixture.session.renameSpace(home, name: "Home", emoji: "🏠", paletteID: "purple-pink")

        fixture.session.renameSpace(home, name: "Base", emoji: "🏠")
        fixture.session.renameSpace(home, name: "Base", emoji: "🏠", paletteID: "ocean")

        #expect(fixture.session.activeSpace.paletteID == "purple-pink")
        #expect(fixture.session.activeSpace.name == "Base")
    }

    @Test func eachSpaceKeepsItsOwnThemeInTheSavedSessionAndAfterARestore() {
        let fixture = SessionFixture()
        let home = fixture.session.activeSpaceID
        fixture.session.renameSpace(home, name: "Home", emoji: "🏠", paletteID: "brown-yellow")
        fixture.session.createSpace(name: "Reading", emoji: "📚", paletteID: "teal-green")

        let saved = fixture.session.savedSession()
        #expect(saved.spaces.map(\.paletteID) == ["brown-yellow", "teal-green"])

        let relaunched = SessionFixture()
        relaunched.session.restore(saved)
        #expect(relaunched.session.spaces.map(\.paletteID) == ["brown-yellow", "teal-green"])
    }
}
