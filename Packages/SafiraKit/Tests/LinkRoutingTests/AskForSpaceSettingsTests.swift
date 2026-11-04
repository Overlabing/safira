// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Testing

@Suite struct AskForSpaceSettingsTests {
    @Test func theLinkPickerDoesNotAskForTheSpaceUntilTheUserTurnsItOn() {
        #expect(AskForSpaceSettings().isEnabled == false)
        #expect(AskForSpaceSettingsStore(defaults: UserDefaults(suiteName: "safira-test-\(UUID().uuidString)")!).load().isEnabled == false)
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
        let defaults = UserDefaults(suiteName: "safira-test-\(UUID().uuidString)")!
        AskForSpaceSettingsStore(defaults: defaults).save(AskForSpaceSettings(isEnabled: true))
        #expect(AskForSpaceSettingsStore(defaults: defaults).load().isEnabled)
    }
}
