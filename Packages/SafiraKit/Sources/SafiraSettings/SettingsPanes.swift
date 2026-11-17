// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import DesignKit
import Foundation
import Preferences

/// The panes of Settings. The raw value is stored to reopen the last pane, so it never changes once shipped.
public enum SettingsPaneID: String, CaseIterable, Sendable {
    case general, spaces, shortcuts, defaults, linkRules, sitePermissions, extensions, debug
    case searchEngine, cookiePrompts, profileExtensions

    /// Where the pane is listed: with the window's Profile when what it changes is stored with the Profile, with Safira
    /// when it is stored once for the app.
    public var group: SettingsGroupID {
        switch self {
        case .searchEngine, .cookiePrompts, .sitePermissions, .spaces, .profileExtensions: .thisProfile
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
        case .spaces, .shortcuts, .defaults, .extensions, .searchEngine, .profileExtensions: []
        }
    }
}

/// The two groups of Settings: what applies to the window's Profile, and what applies to Safira in every Profile.
public enum SettingsGroupID: String, CaseIterable, Sendable {
    case thisProfile, safira
}

/// The menu items that open Settings: Settings… reopens the last pane, the others open their own (they opened separate
/// windows before Settings had panes).
public enum SettingsOpener: String, CaseIterable, Sendable {
    case settings, shortcuts, defaults, linkRules, sitePermissions

    /// The pane the item opens; nil for Settings…, which reopens the last one.
    public var pane: SettingsPaneID? {
        switch self {
        case .settings: nil
        case .shortcuts: .shortcuts
        case .defaults: .defaults
        case .linkRules: .linkRules
        case .sitePermissions: .sitePermissions
        }
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

public enum SafiraSettings {
    /// Where the open pane is stored, in the app's defaults.
    public static let storageKey = "settings.openPane"

    /// The panes in the column's order, by group.
    public static let order: [SettingsGroupID: [SettingsPaneID]] = [
        .thisProfile: [.searchEngine, .cookiePrompts, .sitePermissions, .spaces, .profileExtensions],
        .safira: [.general, .shortcuts, .linkRules, .extensions, .defaults, .debug],
    ]

    /// The groups of a window's Settings. A Private window shows only Safira's: its Profile's settings are not its own.
    public static func groups(isPrivate: Bool) -> [SidebarSwapGroup<SettingsPaneID>] {
        let shown: [SettingsGroupID] = isPrivate ? [.safira] : [.thisProfile, .safira]
        return shown.map { group in
            SidebarSwapGroup(id: group.rawValue, title: title(of: group), sections: (order[group] ?? []).map(section))
        }
    }

    /// Every pane, in the column's order.
    public static var sections: [SidebarSwapSection<SettingsPaneID>] {
        groups(isPrivate: false).flatMap(\.sections)
    }

    public static func title(of group: SettingsGroupID) -> String {
        switch group {
        case .thisProfile: String(localized: "This Profile", table: "SafiraSettings", bundle: .module,
                                  comment: "Settings: heading of the panes that apply to the window's Profile")
        case .safira: String(localized: "Safira", table: "SafiraSettings", bundle: .module,
                             comment: "Settings: heading of the panes that apply to the app, in every Profile")
        }
    }

    public static func section(_ id: SettingsPaneID) -> SidebarSwapSection<SettingsPaneID> {
        switch id {
        case .general:
            SidebarSwapSection(id, title: String(localized: "General", table: "SafiraSettings", bundle: .module,
                                                 comment: "Settings: pane title"),
                               subtitle: String(localized: "Updates and the default browser.", table: "SafiraSettings",
                                                bundle: .module, comment: "Settings: subtitle of the General pane"),
                               systemImage: "gearshape")
        case .searchEngine:
            SidebarSwapSection(id, title: String(localized: "Search Engine", table: "SafiraSettings", bundle: .module,
                                                 comment: "Settings: pane title"),
                               subtitle: String(localized: "What the Command bar searches with in this Profile.",
                                                table: "SafiraSettings", bundle: .module,
                                                comment: "Settings: subtitle of the Search Engine pane"),
                               systemImage: "magnifyingglass")
        case .cookiePrompts:
            SidebarSwapSection(id, title: String(localized: "Cookie Prompts", table: "SafiraSettings", bundle: .module,
                                                 comment: "Settings: pane title"),
                               subtitle: String(localized: "Rejected for you in this Profile, except on the sites you allow.",
                                                table: "SafiraSettings", bundle: .module,
                                                comment: "Settings: subtitle of the Cookie Prompts pane"),
                               systemImage: "checkmark.shield")
        case .spaces:
            SidebarSwapSection(id, title: String(localized: "Spaces", table: "SafiraSettings", bundle: .module,
                                                 comment: "Settings: pane title"),
                               subtitle: String(localized: "This Profile’s Spaces, in the order of ⌃1 to ⌃9.",
                                                table: "SafiraSettings", bundle: .module,
                                                comment: "Settings: subtitle of the Spaces pane"),
                               systemImage: "square.stack.3d.up")
        case .shortcuts:
            SidebarSwapSection(id, title: String(localized: "Shortcuts", table: "SafiraSettings", bundle: .module,
                                                 comment: "Settings: pane title"),
                               subtitle: String(localized: "The preset, and the keys of every command.", table: "SafiraSettings",
                                                bundle: .module, comment: "Settings: subtitle of the Shortcuts pane"),
                               systemImage: "keyboard")
        case .defaults:
            SidebarSwapSection(id, title: String(localized: "Defaults", table: "SafiraSettings", bundle: .module,
                                                 comment: "Settings: pane title; every default Safira chose for the user"),
                               subtitle: String(localized: "Everything Safira decided for you, and where to change it.",
                                                table: "SafiraSettings", bundle: .module,
                                                comment: "Settings: subtitle of the Defaults pane"),
                               systemImage: "checklist")
        case .linkRules:
            SidebarSwapSection(id, title: String(localized: "Link Rules", table: "SafiraSettings", bundle: .module,
                                                 comment: "Settings: pane title"),
                               subtitle: String(localized: "Where links from other apps open.", table: "SafiraSettings",
                                                bundle: .module, comment: "Settings: subtitle of the Link Rules pane"),
                               systemImage: "arrow.triangle.branch")
        case .sitePermissions:
            SidebarSwapSection(id, title: String(localized: "Site Permissions", table: "SafiraSettings", bundle: .module,
                                                 comment: "Settings: pane title"),
                               subtitle: String(localized: "What sites may use in this Profile.", table: "SafiraSettings",
                                                bundle: .module, comment: "Settings: subtitle of the Site Permissions pane"),
                               systemImage: "hand.raised.fill")
        case .profileExtensions:
            SidebarSwapSection(id, title: String(localized: "Extensions", table: "SafiraSettings", bundle: .module,
                                                 comment: "Settings: pane title"),
                               subtitle: String(localized: "Which installed extensions run in this Profile.",
                                                table: "SafiraSettings", bundle: .module,
                                                comment: "Settings: subtitle of the Extensions pane of This Profile"),
                               systemImage: "puzzlepiece.extension")
        case .extensions:
            SidebarSwapSection(id, title: String(localized: "Extensions", table: "SafiraSettings", bundle: .module,
                                                 comment: "Settings: pane title"),
                               subtitle: String(localized: "Installed once for Safira: add, update and remove them.",
                                                table: "SafiraSettings", bundle: .module,
                                                comment: "Settings: subtitle of the Extensions pane of Safira"),
                               systemImage: "puzzlepiece")
        case .debug:
            SidebarSwapSection(id, title: String(localized: "Debug", table: "SafiraSettings", bundle: .module,
                                                 comment: "Settings: pane title"),
                               subtitle: String(localized: "Local logs to attach to a report.", table: "SafiraSettings",
                                                bundle: .module, comment: "Settings: subtitle of the Debug pane"),
                               systemImage: "ladybug")
        }
    }
}

/// One window's Settings: the window's column swapped for the panes (ThemeKit's sidebar swap) and the pane shown. The
/// last pane is stored for the app, so every window opens Settings where it was left; a Private window, which lists only
/// Safira's panes, opens on General when the last one was a Profile's.
@MainActor
public final class SettingsSwap {
    public let model: SidebarSwapModel<SettingsPaneID>
    public let isPrivate: Bool
    private let store: any KeyValueStore

    public init(isPrivate: Bool, store: any KeyValueStore = UserDefaults.standard) {
        self.isPrivate = isPrivate
        self.store = store
        let stored = store.string(forKey: SafiraSettings.storageKey).flatMap(SettingsPaneID.init(rawValue:))
        model = SidebarSwapModel(groups: SafiraSettings.groups(isPrivate: isPrivate), selection: stored ?? .general)
        model.onSelect = { [store] pane in store.setString(pane.rawValue, forKey: SafiraSettings.storageKey) }
    }

    public var isPresented: Bool { model.isPresented }
    public var pane: SettingsPaneID { model.selection }

    /// A menu item: Settings… shows the last pane, or returns when Settings is shown; another item shows its own pane,
    /// or returns when it is the pane shown. Returns whether Settings is shown after it.
    @discardableResult
    public func open(_ opener: SettingsOpener) -> Bool {
        if let pane = opener.pane, !model.sections.contains(where: { $0.id == pane }) {
            model.present()
            return true
        }
        return model.toggle(opener.pane)
    }

    /// Shows Settings on `pane`.
    public func open(pane: SettingsPaneID) {
        model.present(pane)
    }

    /// The back arrow, Escape, or the menu item again.
    public func close() {
        model.dismiss()
    }
}
