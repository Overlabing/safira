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
    @Test func theRailFollowsZensOrder() {
        #expect(SafiraSettings.libraryItems(isPrivate: false).map(\.id) == [.downloads, .spaces, .linkRules, .extensions, .settings])
        #expect(SafiraSettings.libraryItems(isPrivate: false).allSatisfy { !$0.title.isEmpty && !$0.systemImage.isEmpty })
        #expect(LibraryItemID.allCases.allSatisfy { !SafiraSettings.subtitle(of: $0).isEmpty })
    }

    /// Spaces and Link Rules belong to the Profile, which a Private window does not change.
    @Test func aPrivateWindowsRailHasDownloadsExtensionsAndSettings() {
        #expect(SafiraSettings.libraryItems(isPrivate: true).map(\.id) == [.downloads, .extensions, .settings])
    }

    /// No pane is in two places: Spaces, Link Rules and Extensions are rail items only.
    @Test func settingsListsItsOwnPanesOnly() {
        let groups = SafiraSettings.groups(isPrivate: false)
        #expect(groups.map(\.title) == ["This Profile", "Safira"])
        #expect(groups.map { $0.panes.map(\.id) } == [
            [.searchEngine, .cookiePrompts, .sitePermissions],
            [.general, .shortcuts, .defaults, .debug],
        ])
        #expect(SafiraSettings.panes.allSatisfy { !$0.title.isEmpty && !$0.subtitle.isEmpty })
        #expect(SafiraSettings.groups(isPrivate: true).map { $0.panes.map(\.id) } == [[.general, .shortcuts, .defaults, .debug]])
    }

    /// The raw values are stored: they never change once shipped.
    @Test func theStoredNamesOfTheFormerPanesStay() {
        #expect(["general", "spaces", "shortcuts", "defaults", "linkRules", "sitePermissions", "extensions", "debug"]
            .allSatisfy { SettingsPaneID(rawValue: $0) != nil })
    }

    /// The former panes that are rail items now open their item, from the menu or a stored name.
    @Test func theFormerPanesOfTheRailOpenTheirItem() {
        #expect(SettingsPaneID.spaces.destination == .item(.spaces))
        #expect(SettingsPaneID.linkRules.destination == .item(.linkRules))
        #expect(SettingsPaneID.extensions.destination == .item(.extensions))
        #expect(SettingsPaneID.general.destination == .settings(.general))
        #expect(SettingsOpener.linkRules.destination == .item(.linkRules))
        #expect(SettingsOpener.settings.destination == .settings(nil))
        #expect(SettingsOpener.sitePermissions.destination == .settings(.sitePermissions))
    }

    @Test func settingsOpensOnSettingsAndTheSameCommandCloses() {
        let library = LibraryNavigation(isPrivate: false, store: InMemoryKeyValueStore())
        #expect(!library.isPresented)
        #expect(library.toggle(SettingsOpener.settings.destination))
        #expect(library.item == .settings)
        #expect(library.settingsPane == .general)
        #expect(!library.toggle(SettingsOpener.settings.destination))
    }

    @Test func aMenuItemForAPaneSwitchesThePaneAndAgainCloses() {
        let library = LibraryNavigation(isPrivate: false, store: InMemoryKeyValueStore())
        library.toggle(.settings(nil))
        #expect(library.toggle(.settings(.shortcuts)))
        #expect(library.settingsPane == .shortcuts)
        #expect(!library.toggle(.settings(.shortcuts)))
    }

    @Test func downloadsFromAnotherItemSwitchesThenCloses() {
        let library = LibraryNavigation(isPrivate: false, store: InMemoryKeyValueStore())
        library.open(.settings(nil))
        #expect(library.toggle(.item(.downloads)))
        #expect(library.item == .downloads)
        #expect(!library.toggle(.item(.downloads)))
        #expect(library.item == .downloads)
    }

    @Test func theLastItemAndPaneAreStoredForEveryWindow() {
        let store = InMemoryKeyValueStore()
        let library = LibraryNavigation(isPrivate: false, store: store)
        library.open(.settings(.cookiePrompts))
        library.rail.select(.linkRules)
        #expect(store.string(forKey: "settings.openPane") == "cookiePrompts")
        #expect(store.string(forKey: "library.openItem") == "linkRules")
        let other = LibraryNavigation(isPrivate: false, store: store)
        #expect(other.item == .linkRules)
        #expect(other.settingsPane == .cookiePrompts)
    }

    /// A Private window lists fewer: it opens on what it has.
    @Test func aPrivateWindowOpensOnWhatItLists() {
        let store = InMemoryKeyValueStore()
        store.setString("linkRules", forKey: "library.openItem")
        store.setString("cookiePrompts", forKey: "settings.openPane")
        let library = LibraryNavigation(isPrivate: true, store: store)
        #expect(library.item == .downloads)
        #expect(library.settingsPane == .general)
        library.open(.item(.linkRules))
        #expect(library.isPresented)
        #expect(library.item == .downloads)
        #expect(!library.select(pane: .sitePermissions))
        #expect(store.string(forKey: "settings.openPane") == "cookiePrompts")
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
    }

    /// In a Private window the Defaults pane leaves out what is stored with the Profile: changed there, it would reach
    /// the Profile shown in the Main window.
    @Test func aPrivateWindowsDefaultsLeaveOutTheProfilesSettings() {
        #expect(SafiraSettings.profileDefaults == [
            "web.fraudulentSiteWarning", "web.autoplayingSound", "web.cookiePrompts", "search.engine",
        ])
        for id in SafiraSettings.profileDefaults {
            #expect(!SafiraSettings.listsDefault(id, isPrivate: true))
            #expect(SafiraSettings.listsDefault(id, isPrivate: false))
        }
        #expect(SafiraSettings.listsDefault("updates.automaticChecks", isPrivate: true))
        #expect(SafiraSettings.listsDefault("shortcuts.preset", isPrivate: true))
    }

    /// “Change it: Settings › …” names a pane of Settings, “Library › …” an item of the rail, by the title they show.
    @Test func everyChangeItNamesAPlaceThatExists() {
        let panes = Set(SafiraSettings.panes.map(\.title))
        let items = Set(SafiraSettings.libraryItems(isPrivate: false).map(\.title))
        let places = DefaultsRegistry.entries.userFacing.map(\.whereToChange)
        for place in places where place.hasPrefix("Settings › ") {
            #expect(panes.contains(String(place.dropFirst("Settings › ".count))), "\(place)")
        }
        for place in places where place.hasPrefix("Library › ") {
            #expect(items.contains(String(place.dropFirst("Library › ".count))), "\(place)")
        }
        let wording: [DefaultWording.SettingsPane: SettingsPaneID] = [
            .general: .general, .spaces: .spaces, .shortcuts: .shortcuts, .defaults: .defaults, .linkRules: .linkRules,
            .sitePermissions: .sitePermissions, .extensions: .extensions, .debug: .debug, .searchEngine: .searchEngine,
            .cookiePrompts: .cookiePrompts,
        ]
        #expect(wording.count == DefaultWording.SettingsPane.allCases.count)
        for (place, pane) in wording {
            let prefix = pane.destination == .settings(pane) ? "Settings" : "Library"
            #expect(DefaultWording.settings(place) == "\(prefix) › \(SafiraSettings.pane(pane).title)")
        }
        #expect(places.allSatisfy { !$0.contains("Safira menu") && !$0.hasSuffix("…") }, "\(places)")
    }

    /// A switch a pane shows says that pane is where to change it.
    @Test(arguments: SettingsPaneID.allCases)
    func aPaneSwitchNamesItsOwnPlace(pane: SettingsPaneID) throws {
        let prefix = pane.destination == .settings(pane) ? "Settings" : "Library"
        for id in pane.switches {
            let entry = try #require(DefaultsRegistry.entries.userFacing.first { $0.id == id })
            #expect(entry.whereToChange == "\(prefix) › \(SafiraSettings.pane(pane).title)", "\(id)")
        }
    }

    @Test func theEntriesWithAPlaceNameIt() {
        let places = Dictionary(uniqueKeysWithValues: DefaultsRegistry.entries.userFacing.map { ($0.id, $0.whereToChange) })
        #expect(places["shortcuts.preset"] == "Settings › Shortcuts")
        #expect(places["search.engine"] == "Settings › Search Engine")
        #expect(places["web.cookiePrompts"] == "Settings › Cookie Prompts")
        #expect(places["linkMatching.focusOpenTab"] == "Library › Link Rules")
        #expect(places["linkPicker.defaultBrowser"] == "Settings › General")
        #expect(places["nonWebLinks.confirmation"] == "Settings › Site Permissions")
    }
}
