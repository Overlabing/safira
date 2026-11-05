// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Onboarding
import Preferences
import SafiraCore
import Testing

/// The defaults decided for v1 (docs/scope-v1.md §12, architecture-v1.md §7.2 and the issue), written out literally so
/// that changing one means changing this list.
private let documentedDefaults: [(id: String, value: String, control: DefaultControl)] = [
    ("privacy.telemetry", "None", .information),
    ("updates.automaticChecks", "Off", .toggle(isOn: false)),
    ("search.engine", "Chosen by you", .choice),
    ("search.remoteSuggestions", "Off, local suggestions on", .information),
    ("web.httpsFirst", "On", .information),
    ("diagnostics.debugMode", "Off", .toggle(isOn: false)),
    ("web.fraudulentSiteWarning", "On", .toggle(isOn: true)),
    ("web.autoplayingSound", "Blocked", .toggle(isOn: false)),
    ("web.inspector", "On", .information),
    ("linkMatching.focusOpenTab", "On", .toggle(isOn: true)),
    ("linkPicker.askForSpace", "Off", .toggle(isOn: false)),
    ("linkPicker.choiceLog", "Off", .toggle(isOn: false)),
    ("linkRules.nativeApps", "On, when the app is installed", .information),
    ("linkPicker.defaultBrowser", "Offered", .action),
    ("shortcuts.preset", "Chosen by you", .choice),
    ("session.lazyRestoration", "On", .information),
    ("nonWebLinks.confirmation", "Ask each time", .information),
    ("downloads.folder", "~/Downloads", .information),
    ("window.sidebarSide", "Off, on the left", .toggle(isOn: false)),
]

@Suite struct DefaultsRegistryTests {
    @Test func theUserFacingDefaultsAreTheDocumentedOnesInOrderWithTheirValues() {
        let entries = DefaultsRegistry.entries.userFacing

        #expect(entries.map(\.id) == documentedDefaults.map(\.id))
        #expect(entries.map(\.value) == documentedDefaults.map(\.value))
        #expect(entries.map(\.control) == documentedDefaults.map(\.control))
    }

    @Test func everyEntryIsDeclaredOnceAndSaysWhatItIsAndWhereToChangeIt() {
        let entries = DefaultsRegistry.entries

        #expect(Set(entries.map(\.id)).count == entries.count)
        for entry in entries {
            #expect(!entry.title.isEmpty && !entry.explanation.isEmpty && !entry.whereToChange.isEmpty, "\(entry.id)")
        }
    }

    @Test func compactModeKeepsItsIdentifierButIsNotOneOfTheDecidedDefaults() throws {
        let compact = try #require(DefaultsRegistry.entries.entry("window.compactMode"))

        #expect(compact.isUserFacing == false)
        #expect(!DefaultsRegistry.entries.userFacing.contains(compact))
    }

    @Test func theEntriesThatCannotBeChangedYetSayTheyCannot() {
        let fixed = DefaultsRegistry.entries.userFacing.filter { $0.whereToChange == BuiltInDefaults.notAdjustable }

        #expect(fixed.map(\.id) == ["search.remoteSuggestions", "web.httpsFirst", "session.lazyRestoration", "downloads.folder"])
    }

    @Test func noSearchEngineIsNamedInTheDefaultValue() throws {
        let engine = try #require(DefaultsRegistry.entries.entry("search.engine"))

        #expect(SearchEngine.allCases.allSatisfy { !engine.value.contains($0.name) })
    }
}
