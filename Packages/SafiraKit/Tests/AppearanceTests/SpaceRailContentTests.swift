// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import ColorCore
import DesignKit
import Foundation
import SafiraCore
import Testing

/// What the Space rail receives from Safira's Profiles and Spaces.
struct SpaceRailContentTests {
    private static func id(_ n: Int) -> UUID { UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")! }

    private let home = SpaceSummary(id: SpaceID(rawValue: id(1)), name: "Home", emoji: "🏠", paletteID: "teal-green")
    private let reading = SpaceSummary(id: SpaceID(rawValue: id(2)), name: "Reading", emoji: " ")
    private let ops = SpaceSummary(id: SpaceID(rawValue: id(3)), name: "Ops", emoji: "🚀")
    private let family = SpaceSummary(id: SpaceID(rawValue: id(4)), name: "Family", emoji: "🏡")

    private let work = Profile(id: ProfileID(rawValue: id(5)), name: "Work", symbol: "💼", paletteID: "indigo-blue")
    private let personal = Profile(id: ProfileID(rawValue: id(6)), name: "Personal", symbol: "🏡")
    private let school = Profile(id: ProfileID(rawValue: id(7)), name: "School", symbol: "🎓")
    private let travel = Profile(id: ProfileID(rawValue: id(8)), name: "Travel", symbol: "✈️")

    private let shortcuts = SpaceRailContent.Shortcuts(spaces: ["⌃1", "⌃2"], previousProfile: "⌃⌥⌘←",
                                                       nextProfile: "⌃⌥⌘→")

    private func spaces(_ id: ProfileID) -> ProfileSpaces {
        switch id {
        case work.id: ProfileSpaces(spaces: [home, reading, ops], lastSpaceID: reading.id)
        case personal.id: ProfileSpaces(spaces: [family], lastSpaceID: nil)
        default: ProfileSpaces()
        }
    }

    @Test func theActiveProfilesSpacesCarryTheirGlyphThemeAndOnlyTheFirstShortcuts() throws {
        let profiles = SpaceRailContent.profiles([work, personal], activeID: work.id, spaces: spaces, shortcuts: shortcuts)

        let active = try #require(profiles.first)
        #expect(active.id == "00000000-0000-0000-0000-000000000005")
        #expect(active.name == "Work")
        #expect(active.emoji == "💼")
        #expect(active.lastSpaceID == "00000000-0000-0000-0000-000000000002")
        #expect(active.shortcut == nil)
        #expect(active.spaces.map(\.name) == ["Home", "Reading", "Ops"])
        #expect(active.spaces.map(\.glyph) == [.emoji("🏠"), .initial, .emoji("🚀")])
        #expect(active.spaces.map(\.theme.id) == ["teal-green", "indigo-blue", "indigo-blue"])
        #expect(active.spaces.map(\.shortcut) == ["⌃1", "⌃2", nil])
    }

    @Test func anotherProfileHasNoSpaceShortcutsWearsItsOwnThemeAndLandsOnItsFirstSpaceWithNoneSaved() throws {
        let profiles = SpaceRailContent.profiles([work, personal], activeID: work.id, spaces: spaces, shortcuts: shortcuts)

        let other = try #require(profiles.last)
        #expect(other.name == "Personal")
        #expect(other.spaces.map(\.shortcut) == [nil])
        #expect(other.spaces.map(\.theme.id) == [ThemeCatalog.first.id])
        #expect(other.lastSpaceID == nil)
        #expect(other.landingSpace?.name == "Family")
        #expect(other.shortcut == "⌃⌥⌘→")
    }

    @Test func theProfilesAfterAndBeforeTheActiveOneShowNextAndPreviousWrappingAround() {
        let profiles = SpaceRailContent.profiles([work, personal, school], activeID: work.id, spaces: spaces,
                                                 shortcuts: shortcuts)
        #expect(profiles.map(\.shortcut) == [nil, "⌃⌥⌘→", "⌃⌥⌘←"])

        let fromMiddle = SpaceRailContent.profiles([work, personal, school, travel], activeID: personal.id,
                                                   spaces: spaces, shortcuts: shortcuts)
        #expect(fromMiddle.map(\.shortcut) == ["⌃⌥⌘←", nil, "⌃⌥⌘→", nil])
    }

    @Test func theRailModelPutsTheActiveProfilesSpacesInTheRowAndFoldsTheOther() {
        let profiles = SpaceRailContent.profiles([work, personal], activeID: work.id, spaces: spaces, shortcuts: shortcuts)
        let model = SpaceRailModel(profiles: profiles, selection: reading.id.rawValue.uuidString)

        let layout = model.layout(width: 360, hasCommands: true)

        #expect(layout.items.map(\.id) == [
            .space(home.id.rawValue.uuidString), .space(reading.id.rawValue.uuidString), .space(ops.id.rawValue.uuidString),
            .profile(personal.id.rawValue.uuidString), .add,
        ])
        #expect(layout.selectedKey == .space(reading.id.rawValue.uuidString))
        #expect(model.action(for: layout.profiles[0]) == .selectProfile(personal.id.rawValue.uuidString,
                                                                        landing: family.id.rawValue.uuidString))
    }
}
