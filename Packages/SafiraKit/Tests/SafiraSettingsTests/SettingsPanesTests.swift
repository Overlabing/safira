// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppShellKit
import Commands
import Onboarding
import Preferences
import SafiraSettings
import Testing

@MainActor
@Suite struct SettingsPanesTests {
    @Test func theWindowHasOnePanePerAreaInThisOrder() {
        #expect(SafiraSettings.panes.map(\.id.rawValue)
            == ["general", "shortcuts", "defaults", "linkRules", "sitePermissions", "debug"])
        #expect(SafiraSettings.panes.allSatisfy { !$0.title.isEmpty && $0.subtitle?.isEmpty == false })
    }

    @Test(arguments: SettingsPaneID.allCases)
    func eachPaneIsReachable(pane: SettingsPaneID) {
        let presenter = SettingsPresenter(store: InMemoryKeyValueStore()) {}
        #expect(presenter.model.open(pane: pane))
        #expect(presenter.model.selection == pane)
        #expect(presenter.model.current.id == pane)
    }

    @Test(arguments: SettingsOpener.allCases.filter { $0 != .settings })
    func eachFormerWindowsMenuItemOpensItsPane(opener: SettingsOpener) {
        var shown = 0
        let presenter = SettingsPresenter(store: InMemoryKeyValueStore()) { shown += 1 }
        presenter.open(opener)
        #expect(shown == 1)
        #expect(presenter.model.selection == opener.pane)
    }

    @Test func theFormerWindowsOpenTheirOwnPane() {
        #expect(SettingsOpener.shortcuts.pane == .shortcuts)
        #expect(SettingsOpener.defaults.pane == .defaults)
        #expect(SettingsOpener.linkRules.pane == .linkRules)
        #expect(SettingsOpener.sitePermissions.pane == .sitePermissions)
        #expect(SettingsOpener.sitePermissions.command == .sitePermissions)
    }

    @Test func settingsReopensTheLastPane() {
        let store = InMemoryKeyValueStore()
        var shown = 0
        SettingsPresenter(store: store) {}.open(.linkRules)
        let next = SettingsPresenter(store: store) { shown += 1 }
        next.open(.settings)
        #expect(shown == 1)
        #expect(next.model.selection == .linkRules)
        #expect(store.string(forKey: "settings.openPane") == "linkRules")
        #expect(SettingsOpener.settings.command == .settings)
    }

    @Test func aFirstOpeningShowsGeneral() {
        let presenter = SettingsPresenter(store: InMemoryKeyValueStore()) {}
        presenter.open(.settings)
        #expect(presenter.model.selection == .general)
    }

    /// The settings the menu holds as switches are in a pane too, each once, and each is a switch of the registry.
    @Test func eachMenuSwitchIsInOnePane() {
        let placed = SettingsPaneID.allCases.flatMap(\.switches)
        #expect(placed.count == Set(placed).count)
        #expect(Set(placed) == [
            "updates.automaticChecks", "linkMatching.focusOpenTab", "linkPicker.askForSpace", "linkPicker.choiceLog",
            "web.fraudulentSiteWarning", "web.autoplayingSound", "diagnostics.debugMode",
        ])
        let toggles = Set(DefaultsRegistry.entries.userFacing.compactMap { entry -> String? in
            if case .toggle = entry.control { entry.id } else { nil }
        })
        #expect(Set(placed).isSubset(of: toggles))
        #expect(SettingsPaneID.linkRules.switches
            == ["linkMatching.focusOpenTab", "linkPicker.askForSpace", "linkPicker.choiceLog"])
        #expect(SettingsPaneID.sitePermissions.switches == ["web.fraudulentSiteWarning", "web.autoplayingSound"])
    }
}
