// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppShellKit
import Commands
import Onboarding
import Preferences
import SafiraCore
import SafiraSettings
import Testing

@MainActor
@Suite struct SettingsPanesTests {
    @Test func theWindowHasOnePanePerAreaInThisOrder() {
        #expect(SafiraSettings.panes.map(\.id.rawValue)
            == ["general", "spaces", "shortcuts", "defaults", "linkRules", "sitePermissions", "extensions", "debug"])
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
            "web.fraudulentSiteWarning", "web.autoplayingSound", "web.cookiePrompts", "diagnostics.debugMode",
        ])
        let toggles = Set(DefaultsRegistry.entries.userFacing.compactMap { entry -> String? in
            if case .toggle = entry.control { entry.id } else { nil }
        })
        #expect(Set(placed).isSubset(of: toggles))
        #expect(SettingsPaneID.linkRules.switches
            == ["linkMatching.focusOpenTab", "linkPicker.askForSpace", "linkPicker.choiceLog"])
        #expect(SettingsPaneID.sitePermissions.switches
            == ["web.fraudulentSiteWarning", "web.autoplayingSound", "web.cookiePrompts"])
    }

    /// “Change it: Settings › …” names a pane the window has, by the title its sidebar shows; no default still points
    /// at a menu item that now only opens the window.
    @Test func everyChangeItInSettingsNamesAPaneThatExists() {
        let titles = Set(SafiraSettings.panes.map(\.title))
        let places = DefaultsRegistry.entries.userFacing.map(\.whereToChange)
        for place in places where place.hasPrefix("Settings › ") {
            #expect(titles.contains(String(place.dropFirst("Settings › ".count))), "\(place)")
        }
        #expect(DefaultWording.SettingsPane.allCases.map { DefaultWording.settings($0) }
            == SafiraSettings.panes.map { "Settings › \($0.title)" })
        #expect(places.allSatisfy { !$0.contains("Safira menu") && !$0.hasSuffix("…") }, "\(places)")
    }

    /// A switch a pane shows says that pane is where to change it.
    @Test(arguments: SettingsPaneID.allCases)
    func aPaneSwitchNamesItsOwnPane(pane: SettingsPaneID) throws {
        let title = try #require(SafiraSettings.panes.first { $0.id == pane }).title
        for id in pane.switches {
            let entry = try #require(DefaultsRegistry.entries.userFacing.first { $0.id == id })
            #expect(entry.whereToChange == "Settings › \(title)", "\(id)")
        }
    }

    @Test func theEntriesWithAPlaceInTheWindowNameIt() {
        let places = Dictionary(uniqueKeysWithValues: DefaultsRegistry.entries.userFacing.map { ($0.id, $0.whereToChange) })
        #expect(places["shortcuts.preset"] == "Settings › Shortcuts")
        #expect(places["search.engine"] == "Settings › Defaults")
        #expect(places["linkPicker.defaultBrowser"] == "Settings › General")
        #expect(places["nonWebLinks.confirmation"] == "Settings › Site Permissions")
    }
}
