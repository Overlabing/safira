// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Preferences
import SafiraCore
import Testing

@Suite struct AskForSpaceSettingsTests {
    @Test func theLinkPickerDoesNotAskForTheSpaceUntilTheUserTurnsItOn() {
        #expect(AskForSpaceSettings().isEnabled == false)
        #expect(AskForSpaceSettingsStore(store: InMemoryKeyValueStore()).load(unreadable: { _ in }).isEnabled == false)
    }

    @Test func theDefaultIsListedInTheRegistryOfDefaults() throws {
        let entry = try #require(AskForSpaceSettings.defaultEntries.first)
        #expect(entry.id == "linkPicker.askForSpace")
        #expect(entry.title == "Ask for the Space Too")
        #expect(entry.value == "Off")
        #expect(entry.whereToChange == "Safira menu")
    }

    @Test func nativeAppRewritingIsListedInTheRegistryOfDefaults() throws {
        let entry = try #require(NativeApp.defaultEntries.first)
        #expect(entry.id == "linkRules.nativeApps")
        #expect(entry.whereToChange == "Rules file")
    }

    @Test func theSettingIsKeptAcrossLaunches() {
        let store = InMemoryKeyValueStore()
        AskForSpaceSettingsStore(store: store).save(AskForSpaceSettings(isEnabled: true))
        #expect(AskForSpaceSettingsStore(store: store).load(unreadable: { _ in }).isEnabled)
    }

    @Test func aSettingTheOldStoreTurnedOnStaysOnAfterTheMigration() throws {
        let domain = "safira-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "linkPicker.askForSpace")

        LegacyPreference.migrate([AskForSpaceSettingsStore.legacy], in: defaults, domain: domain)

        #expect(AskForSpaceSettingsStore(store: defaults).load(unreadable: { _ in }).isEnabled)
    }
}
