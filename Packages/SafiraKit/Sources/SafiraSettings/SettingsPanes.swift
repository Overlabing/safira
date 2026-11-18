// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import DesignKit
import Foundation
import Preferences

/// The items of the Library's rail, as in Zen: the window's sidebar gives way to them. The raw value is stored to reopen
/// the last item, so it never changes once shipped.
public enum LibraryItemID: String, CaseIterable, Sendable {
    case downloads, spaces, linkRules, extensions, settings
}

/// The panes a name can ask for: the stored names of the former Settings window's panes, for the menu and for the last
/// pane saved. Three of them are rail items of their own now (`destination`); the others are panes of Settings.
public enum SettingsPaneID: String, CaseIterable, Sendable {
    case general, spaces, shortcuts, defaults, linkRules, sitePermissions, extensions, debug
    case searchEngine, cookiePrompts

    /// Where the Library shows it.
    public var destination: LibraryDestination {
        switch self {
        case .spaces: .item(.spaces)
        case .linkRules: .item(.linkRules)
        case .extensions: .item(.extensions)
        default: .settings(self)
        }
    }

    /// Where a pane of Settings is listed: with the window's Profile when what it changes is stored with the Profile,
    /// with Safira when it is stored once for the app.
    public var group: SettingsGroupID {
        switch self {
        case .searchEngine, .cookiePrompts, .sitePermissions, .spaces: .thisProfile
        case .general, .shortcuts, .linkRules, .extensions, .defaults, .debug: .safira
        }
    }

    /// The switches of the registry of defaults (`DefaultEntry.id`) a pane shows besides its own content. The menu keeps
    /// its items for them, which show the same state.
    public var switches: [String] {
        switch self {
        case .general: ["updates.automaticChecks"]
        case .linkRules: ["linkMatching.focusOpenTab", "linkPicker.askForSpace", "linkPicker.choiceLog"]
        case .sitePermissions: ["web.fraudulentSiteWarning", "web.autoplayingSound"]
        case .cookiePrompts: ["web.cookiePrompts"]
        case .debug: ["diagnostics.debugMode"]
        case .spaces, .shortcuts, .defaults, .extensions, .searchEngine: []
        }
    }
}

/// What the Library shows: a rail item, or Settings on one of its panes (nil: the pane it showed last).
public enum LibraryDestination: Hashable, Sendable {
    case item(LibraryItemID)
    case settings(SettingsPaneID?)

    public var item: LibraryItemID {
        switch self {
        case .item(let item): item
        case .settings: .settings
        }
    }
}

/// The two groups of Settings: what applies to the window's Profile, and what applies to Safira in every Profile.
public enum SettingsGroupID: String, CaseIterable, Sendable {
    case thisProfile, safira
}

/// The menu items that open the Library: Settings… on Settings as it was left, the others on their own pane or item.
public enum SettingsOpener: String, CaseIterable, Sendable {
    case settings, shortcuts, defaults, linkRules, sitePermissions

    /// The pane the item asks for; nil for Settings…, which leaves the pane as it was.
    public var pane: SettingsPaneID? {
        switch self {
        case .settings: nil
        case .shortcuts: .shortcuts
        case .defaults: .defaults
        case .linkRules: .linkRules
        case .sitePermissions: .sitePermissions
        }
    }

    public var destination: LibraryDestination {
        pane?.destination ?? .settings(nil)
    }

    /// The command behind the item, whose key the menu shows; nil for an item without a shortcut.
    public var command: CommandID? {
        switch self {
        case .settings: .settings
        case .sitePermissions: .sitePermissions
        case .shortcuts, .defaults, .linkRules: nil
        }
    }
}

/// A pane of Settings as its list shows it: its symbol and title, and the subtitle over its content.
public struct SettingsPaneInfo: Identifiable, Hashable, Sendable {
    public let id: SettingsPaneID
    public let title: String
    public let subtitle: String
    public let systemImage: String
}

/// The panes under one heading of Settings' list.
public struct SettingsGroup: Identifiable, Hashable, Sendable {
    public let id: SettingsGroupID
    public let title: String
    public let panes: [SettingsPaneInfo]
}

public enum SafiraSettings {
    /// Where the last pane of Settings is stored, in the app's defaults. The key was the Settings window's.
    public static let storageKey = "settings.openPane"
    /// Where the last item of the Library is stored.
    public static let libraryKey = "library.openItem"

    /// The panes of Settings in the list's order, by group. Spaces, Link Rules and Extensions are not among them: they
    /// are rail items of their own.
    public static let order: [SettingsGroupID: [SettingsPaneID]] = [
        .thisProfile: [.searchEngine, .cookiePrompts, .sitePermissions],
        .safira: [.general, .shortcuts, .defaults, .debug],
    ]

    /// The groups of a window's Settings. A Private window shows only Safira's: its Profile's settings are not its own.
    public static func groups(isPrivate: Bool) -> [SettingsGroup] {
        let shown: [SettingsGroupID] = isPrivate ? [.safira] : [.thisProfile, .safira]
        return shown.map { group in
            SettingsGroup(id: group, title: title(of: group), panes: (order[group] ?? []).map(pane))
        }
    }

    /// Every pane of Settings, in the list's order.
    public static var panes: [SettingsPaneInfo] {
        groups(isPrivate: false).flatMap(\.panes)
    }

    /// The rail of a window's Library, in Zen's order. A Private window has no Spaces and no Link Rules: they belong
    /// to the Profile.
    public static func libraryItems(isPrivate: Bool) -> [LibraryItem<LibraryItemID>] {
        let shown: [LibraryItemID] = isPrivate ? [.downloads, .extensions, .settings]
            : [.downloads, .spaces, .linkRules, .extensions, .settings]
        return shown.map(item)
    }

    /// The defaults a window's Defaults pane lists: in a Private window, none of those stored with the Profile (its web
    /// content switches and its search engine), since what a Private window changes never reaches its Profile.
    public static func listsDefault(_ id: String, isPrivate: Bool) -> Bool {
        !isPrivate || !profileDefaults.contains(id)
    }

    /// The defaults stored with the Profile: the switches of This Profile's panes, and the search engine.
    public static var profileDefaults: Set<String> {
        Set((order[.thisProfile] ?? []).flatMap(\.switches) + ["search.engine"])
    }

    public static func title(of group: SettingsGroupID) -> String {
        switch group {
        case .thisProfile: String(localized: "This Profile", table: "SafiraSettings", bundle: .module,
                                  comment: "Settings: heading of the panes that apply to the window's Profile")
        case .safira: String(localized: "Safira", table: "SafiraSettings", bundle: .module,
                             comment: "Settings: heading of the panes that apply to the app, in every Profile")
        }
    }

    public static func item(_ id: LibraryItemID) -> LibraryItem<LibraryItemID> {
        switch id {
        case .downloads:
            LibraryItem(id, title: String(localized: "Downloads", table: "SafiraSettings", bundle: .module,
                                          comment: "Library: rail item"), systemImage: "arrow.down.circle")
        case .spaces:
            LibraryItem(id, title: String(localized: "Spaces", table: "SafiraSettings", bundle: .module,
                                          comment: "Library: rail item"), systemImage: "square.stack.3d.up")
        case .linkRules:
            LibraryItem(id, title: String(localized: "Link Rules", table: "SafiraSettings", bundle: .module,
                                          comment: "Library: rail item"), systemImage: "arrow.triangle.branch")
        case .extensions:
            LibraryItem(id, title: String(localized: "Extensions", table: "SafiraSettings", bundle: .module,
                                          comment: "Library: rail item"), systemImage: "puzzlepiece.extension")
        case .settings:
            LibraryItem(id, title: String(localized: "Settings", table: "SafiraSettings", bundle: .module,
                                          comment: "Library: rail item"), systemImage: "gearshape")
        }
    }

    /// The subtitle of a rail item's content, under its title.
    public static func subtitle(of id: LibraryItemID) -> String {
        switch id {
        case .downloads: String(localized: "This window’s downloads, newest first.", table: "SafiraSettings",
                                bundle: .module, comment: "Library: subtitle of Downloads")
        case .spaces: String(localized: "This Profile’s Spaces, in the order of ⌃1 to ⌃9.", table: "SafiraSettings",
                             bundle: .module, comment: "Library: subtitle of Spaces")
        case .linkRules: String(localized: "Where links from other apps open.", table: "SafiraSettings",
                                bundle: .module, comment: "Library: subtitle of Link Rules")
        case .extensions: String(localized: "Installed once for Safira, switched on per Profile.", table: "SafiraSettings",
                                 bundle: .module, comment: "Library: subtitle of Extensions")
        case .settings: String(localized: "This Profile’s settings, and Safira’s.", table: "SafiraSettings",
                               bundle: .module, comment: "Library: subtitle of Settings")
        }
    }

    public static func pane(_ id: SettingsPaneID) -> SettingsPaneInfo {
        switch id {
        case .general:
            SettingsPaneInfo(id: id, title: String(localized: "General", table: "SafiraSettings", bundle: .module,
                                                   comment: "Settings: pane title"),
                             subtitle: String(localized: "Updates and the default browser.", table: "SafiraSettings",
                                              bundle: .module, comment: "Settings: subtitle of the General pane"),
                             systemImage: "gearshape")
        case .searchEngine:
            SettingsPaneInfo(id: id, title: String(localized: "Search Engine", table: "SafiraSettings", bundle: .module,
                                                   comment: "Settings: pane title"),
                             subtitle: String(localized: "What the Command bar searches with in this Profile.",
                                              table: "SafiraSettings", bundle: .module,
                                              comment: "Settings: subtitle of the Search Engine pane"),
                             systemImage: "magnifyingglass")
        case .cookiePrompts:
            SettingsPaneInfo(id: id, title: String(localized: "Cookie Prompts", table: "SafiraSettings", bundle: .module,
                                                   comment: "Settings: pane title"),
                             subtitle: String(localized: "Rejected for you in this Profile, except on the sites you allow.",
                                              table: "SafiraSettings", bundle: .module,
                                              comment: "Settings: subtitle of the Cookie Prompts pane"),
                             systemImage: "checkmark.shield")
        case .sitePermissions:
            SettingsPaneInfo(id: id, title: String(localized: "Site Permissions", table: "SafiraSettings", bundle: .module,
                                                   comment: "Settings: pane title"),
                             subtitle: String(localized: "What sites may use in this Profile.", table: "SafiraSettings",
                                              bundle: .module, comment: "Settings: subtitle of the Site Permissions pane"),
                             systemImage: "hand.raised")
        case .shortcuts:
            SettingsPaneInfo(id: id, title: String(localized: "Shortcuts", table: "SafiraSettings", bundle: .module,
                                                   comment: "Settings: pane title"),
                             subtitle: String(localized: "The preset, and the keys of every command.", table: "SafiraSettings",
                                              bundle: .module, comment: "Settings: subtitle of the Shortcuts pane"),
                             systemImage: "keyboard")
        case .defaults:
            SettingsPaneInfo(id: id, title: String(localized: "Defaults", table: "SafiraSettings", bundle: .module,
                                                   comment: "Settings: pane title; every default Safira chose for the user"),
                             subtitle: String(localized: "Everything Safira decided for you, and where to change it.",
                                              table: "SafiraSettings", bundle: .module,
                                              comment: "Settings: subtitle of the Defaults pane"),
                             systemImage: "checklist")
        case .debug:
            SettingsPaneInfo(id: id, title: String(localized: "Debug", table: "SafiraSettings", bundle: .module,
                                                   comment: "Settings: pane title"),
                             subtitle: String(localized: "Local logs to attach to a report.", table: "SafiraSettings",
                                              bundle: .module, comment: "Settings: subtitle of the Debug pane"),
                             systemImage: "ladybug")
        case .spaces, .linkRules, .extensions:
            SettingsPaneInfo(id: id, title: item(id.destination.item).title, subtitle: subtitle(of: id.destination.item),
                             systemImage: item(id.destination.item).systemImage)
        }
    }
}

/// One window's Library: its rail (ThemeKit's `LibraryModel`) and the pane Settings shows. The last item and the last
/// pane are stored for the app, so every window opens the Library where it was left; a Private window, which lists
/// fewer, opens on what it has.
@MainActor
@Observable
public final class LibraryNavigation {
    public let rail: LibraryModel<LibraryItemID>
    public let isPrivate: Bool
    /// The pane Settings shows.
    public private(set) var settingsPane: SettingsPaneID
    @ObservationIgnored private let store: any KeyValueStore

    public init(isPrivate: Bool, store: any KeyValueStore = UserDefaults.standard) {
        self.isPrivate = isPrivate
        self.store = store
        let item = store.string(forKey: SafiraSettings.libraryKey).flatMap(LibraryItemID.init(rawValue:))
        rail = LibraryModel(items: SafiraSettings.libraryItems(isPrivate: isPrivate), selection: item ?? .settings)
        let listed = SafiraSettings.groups(isPrivate: isPrivate).flatMap(\.panes).map(\.id)
        let pane = store.string(forKey: SafiraSettings.storageKey).flatMap(SettingsPaneID.init(rawValue:))
        settingsPane = pane.flatMap { listed.contains($0) ? $0 : nil } ?? .general
        rail.onSelect = { [store] item in store.setString(item.rawValue, forKey: SafiraSettings.libraryKey) }
    }

    public var isPresented: Bool { rail.isPresented }
    public var item: LibraryItemID { rail.selection }

    /// Shows `pane` in Settings, if this window lists it.
    @discardableResult
    public func select(pane: SettingsPaneID) -> Bool {
        guard SafiraSettings.groups(isPrivate: isPrivate).contains(where: { $0.panes.contains { $0.id == pane } }) else {
            return false
        }
        if pane != settingsPane {
            settingsPane = pane
            store.setString(pane.rawValue, forKey: SafiraSettings.storageKey)
        }
        return true
    }

    /// Opens the Library on `destination`. A rail item this window does not list (Link Rules in a Private window, say)
    /// opens the Library where it was.
    public func open(_ destination: LibraryDestination) {
        if case .settings(let pane?) = destination { select(pane: pane) }
        rail.present(destination.item)
    }

    /// A menu item or a shortcut: shown on what it asks for, the Library closes; otherwise it opens there. Returns
    /// whether the Library is open after it.
    @discardableResult
    public func toggle(_ destination: LibraryDestination) -> Bool {
        let showsIt: Bool = switch destination {
        case .item(let item): isPresented && self.item == item
        case .settings(let pane): isPresented && item == .settings && (pane == nil || pane == settingsPane)
        }
        if showsIt {
            close()
        } else {
            open(destination)
        }
        return isPresented
    }

    /// The back arrow, Escape, ⌘[, a swipe back, or a click on the page left in sight.
    public func close() {
        rail.dismiss()
    }
}
