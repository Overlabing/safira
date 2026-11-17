// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import DesignKit
import Onboarding
import Preferences
import SafiraCore
import SafiraSettings
import Testing

@MainActor
@Suite struct SettingsPanesTests {
    @Test func theColumnListsThisProfileThenSafira() {
        let groups = SafiraSettings.groups(isPrivate: false)
        #expect(groups.map(\.title) == ["This Profile", "Safira"])
        #expect(groups.map { $0.sections.map(\.id.rawValue) } == [
            ["searchEngine", "cookiePrompts", "sitePermissions", "spaces", "profileExtensions"],
            ["general", "shortcuts", "linkRules", "extensions", "defaults", "debug"],
        ])
        #expect(SafiraSettings.sections.allSatisfy { !$0.title.isEmpty && $0.subtitle?.isEmpty == false })
        #expect(Set(SafiraSettings.sections.map(\.id)) == Set(SettingsPaneID.allCases))
    }

    @Test(arguments: SettingsPaneID.allCases)
    func eachPaneIsListedUnderItsGroup(pane: SettingsPaneID) {
        let group = SafiraSettings.groups(isPrivate: false).first { $0.sections.contains { $0.id == pane } }
        #expect(group?.id == pane.group.rawValue)
    }

    /// A Private window's Profile is not its own to change: its Settings lists Safira's panes only.
    @Test func aPrivateWindowListsOnlySafira() {
        let groups = SafiraSettings.groups(isPrivate: true)
        #expect(groups.map(\.title) == ["Safira"])
        #expect(groups[0].sections.map(\.id) == [.general, .shortcuts, .linkRules, .extensions, .defaults, .debug])
    }

    /// The raw values are stored: they never change once shipped.
    @Test func theStoredNamesOfTheFormerPanesStay() {
        #expect(["general", "spaces", "shortcuts", "defaults", "linkRules", "sitePermissions", "extensions", "debug"]
            .allSatisfy { SettingsPaneID(rawValue: $0) != nil })
    }

    @Test func settingsOpensOnTheLastPaneAndTheSameCommandReturns() {
        let store = InMemoryKeyValueStore()
        let swap = SettingsSwap(isPrivate: false, store: store)
        #expect(!swap.isPresented)
        #expect(swap.open(.settings))
        #expect(swap.pane == .general)
        #expect(!swap.open(.settings))
        #expect(!swap.isPresented)
    }

    @Test func switchingPaneIsStoredForEveryWindow() {
        let store = InMemoryKeyValueStore()
        let swap = SettingsSwap(isPrivate: false, store: store)
        swap.open(.settings)
        #expect(swap.model.select(.cookiePrompts))
        #expect(store.string(forKey: "settings.openPane") == "cookiePrompts")
        swap.close()
        #expect(!swap.isPresented)
        let other = SettingsSwap(isPrivate: false, store: store)
        other.open(.settings)
        #expect(other.pane == .cookiePrompts)
    }

    @Test(arguments: SettingsOpener.allCases.filter { $0 != .settings })
    func eachFormerWindowsMenuItemOpensItsPane(opener: SettingsOpener) {
        let swap = SettingsSwap(isPrivate: false, store: InMemoryKeyValueStore())
        #expect(swap.open(opener))
        #expect(swap.pane == opener.pane)
        // Another pane's item switches the pane; its own item again returns.
        #expect(swap.open(opener == .shortcuts ? .defaults : .shortcuts))
        #expect(swap.open(opener))
        #expect(!swap.open(opener))
    }

    /// The Profile switch in the header changes what "This Profile" means, not where Settings is: the window's swap stays
    /// shown on its pane.
    @Test func switchingProfileKeepsSettingsOnItsPane() {
        let swap = SettingsSwap(isPrivate: false, store: InMemoryKeyValueStore())
        swap.open(pane: .sitePermissions)
        swap.model.setGroups(SafiraSettings.groups(isPrivate: false))
        #expect(swap.isPresented)
        #expect(swap.pane == .sitePermissions)
    }

    @Test func aPrivateWindowOpensOnGeneralWhenTheLastPaneWasAProfiles() {
        let store = InMemoryKeyValueStore()
        store.setString("spaces", forKey: "settings.openPane")
        let swap = SettingsSwap(isPrivate: true, store: store)
        swap.open(.settings)
        #expect(swap.pane == .general)
        #expect(store.string(forKey: "settings.openPane") == "spaces")
        // A Profile's pane asked from a Private window shows Settings where it is.
        swap.close()
        #expect(swap.open(.sitePermissions))
        #expect(swap.pane == .general)
        #expect(swap.open(.sitePermissions))
        #expect(swap.isPresented)
    }

    @Test func theFormerWindowsOpenTheirOwnPane() {
        #expect(SettingsOpener.shortcuts.pane == .shortcuts)
        #expect(SettingsOpener.defaults.pane == .defaults)
        #expect(SettingsOpener.linkRules.pane == .linkRules)
        #expect(SettingsOpener.sitePermissions.pane == .sitePermissions)
        #expect(SettingsOpener.sitePermissions.command == .sitePermissions)
        #expect(SettingsOpener.settings.command == .settings)
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
        #expect(SettingsPaneID.sitePermissions.switches == ["web.fraudulentSiteWarning", "web.autoplayingSound"])
        #expect(SettingsPaneID.cookiePrompts.switches == ["web.cookiePrompts"])
    }

    /// The web content switches are stored with the Profile, so they are listed under This Profile.
    @Test func theProfilesSwitchesAreUnderThisProfile() {
        for pane in SettingsPaneID.allCases where pane.switches.contains(where: { $0.hasPrefix("web.") }) {
            #expect(pane.group == .thisProfile, "\(pane)")
        }
    }

    /// “Change it: Settings › …” names a pane Settings has, by the title its column shows.
    @Test func everyChangeItInSettingsNamesAPaneThatExists() {
        let titles = Set(SafiraSettings.sections.map(\.title))
        let places = DefaultsRegistry.entries.userFacing.map(\.whereToChange)
        for place in places where place.hasPrefix("Settings › ") {
            #expect(titles.contains(String(place.dropFirst("Settings › ".count))), "\(place)")
        }
        let wording: [DefaultWording.SettingsPane: SettingsPaneID] = [
            .general: .general, .spaces: .spaces, .shortcuts: .shortcuts, .defaults: .defaults, .linkRules: .linkRules,
            .sitePermissions: .sitePermissions, .extensions: .extensions, .debug: .debug, .searchEngine: .searchEngine,
            .cookiePrompts: .cookiePrompts, .profileExtensions: .profileExtensions,
        ]
        #expect(wording.count == DefaultWording.SettingsPane.allCases.count)
        for (place, pane) in wording {
            #expect(DefaultWording.settings(place) == "Settings › \(SafiraSettings.section(pane).title)")
        }
        #expect(places.allSatisfy { !$0.contains("Safira menu") && !$0.hasSuffix("…") }, "\(places)")
    }

    /// A switch a pane shows says that pane is where to change it.
    @Test(arguments: SettingsPaneID.allCases)
    func aPaneSwitchNamesItsOwnPane(pane: SettingsPaneID) throws {
        let title = SafiraSettings.section(pane).title
        for id in pane.switches {
            let entry = try #require(DefaultsRegistry.entries.userFacing.first { $0.id == id })
            #expect(entry.whereToChange == "Settings › \(title)", "\(id)")
        }
    }

    @Test func theEntriesWithAPlaceInSettingsNameIt() {
        let places = Dictionary(uniqueKeysWithValues: DefaultsRegistry.entries.userFacing.map { ($0.id, $0.whereToChange) })
        #expect(places["shortcuts.preset"] == "Settings › Shortcuts")
        #expect(places["search.engine"] == "Settings › Search Engine")
        #expect(places["web.cookiePrompts"] == "Settings › Cookie Prompts")
        #expect(places["linkPicker.defaultBrowser"] == "Settings › General")
        #expect(places["nonWebLinks.confirmation"] == "Settings › Site Permissions")
    }
}
