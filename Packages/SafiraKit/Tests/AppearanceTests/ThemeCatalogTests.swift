// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import ColorCore
import Testing

struct ThemeCatalogTests {
    /// The ids are what Profiles and Spaces store: a change here would orphan saved data.
    @Test func thePaletteOffersThesePersistedIDsInOrder() {
        #expect(ThemeCatalog.ids == [
            "indigo-blue", "orange-pink", "teal-green", "red-orange", "purple-pink", "mint-cyan", "brown-yellow",
        ])
    }

    @Test func aSavedIDFindsItsTheme() {
        #expect(ThemeCatalog.theme(id: "teal-green") == Theme(id: "teal-green", primary: .teal, secondary: .green))
    }

    @Test func noIDAndAnUnknownIDFindNoTheme() {
        #expect(ThemeCatalog.theme(id: nil) == nil)
        #expect(ThemeCatalog.theme(id: "ocean") == nil)
    }

    @Test func aMissingThemeFallsBackToTheOneGiven() {
        let fallback = Theme(id: "orange-pink", primary: .orange, secondary: .pink)
        #expect(ThemeCatalog.theme(id: nil, fallback: fallback) == fallback)
        #expect(ThemeCatalog.theme(id: "ocean", fallback: fallback) == fallback)
        #expect(ThemeCatalog.theme(id: "mint-cyan", fallback: fallback).id == "mint-cyan")
    }

    @Test func aNewThemeAvoidsTheOnesInUse() {
        #expect(ThemeCatalog.nextID(avoiding: []) == "indigo-blue")
        #expect(ThemeCatalog.nextID(avoiding: ["indigo-blue"]) == "orange-pink")
        #expect(ThemeCatalog.nextID(avoiding: ["indigo-blue", nil, "teal-green"]) == "orange-pink")
        #expect(ThemeCatalog.nextID(avoiding: ["orange-pink", "indigo-blue", "teal-green"]) == "red-orange")
    }

    @Test func onceEveryThemeIsInUseTheLeastUsedComesFirst() {
        let all = ThemeCatalog.ids
        #expect(ThemeCatalog.nextID(avoiding: all) == "indigo-blue")
        #expect(ThemeCatalog.nextID(avoiding: all + ["indigo-blue", "orange-pink"]) == "teal-green")
    }
}
