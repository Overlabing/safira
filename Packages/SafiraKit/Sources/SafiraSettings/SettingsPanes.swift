// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppShellKit
import Commands
import Foundation
import Preferences
import SwiftUI

/// The panes of the Settings window, in sidebar order. The raw value is stored to reopen the last pane, so it never
/// changes once shipped.
public enum SettingsPaneID: String, SettingsPaneIdentifier, CaseIterable {
    case general, spaces, shortcuts, defaults, linkRules, sitePermissions, extensions, debug

    /// The switches of the registry of defaults (`DefaultEntry.id`) a pane shows besides its own content. The menu keeps
    /// its items for them, which show the same state.
    public var switches: [String] {
        switch self {
        case .general: ["updates.automaticChecks"]
        case .linkRules: ["linkMatching.focusOpenTab", "linkPicker.askForSpace", "linkPicker.choiceLog"]
        case .sitePermissions: ["web.fraudulentSiteWarning", "web.autoplayingSound"]
        case .debug: ["diagnostics.debugMode"]
        case .spaces, .shortcuts, .defaults, .extensions: []
        }
    }
}

/// The menu items that open the Settings window: Settings… reopens the last pane, the others open their own (they
/// opened separate windows before the Settings window).
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

    public static var panes: [SettingsPane<SettingsPaneID>] {
        SettingsPaneID.allCases.map(pane)
    }

    static func pane(_ id: SettingsPaneID) -> SettingsPane<SettingsPaneID> {
        switch id {
        case .general:
            SettingsPane(id, title: String(localized: "General", table: "SafiraSettings", bundle: .module,
                                           comment: "Settings: pane title"),
                         subtitle: String(localized: "Updates and the default browser.", table: "SafiraSettings",
                                          bundle: .module, comment: "Settings: subtitle of the General pane"),
                         systemImage: "gearshape", tint: .gray)
        case .spaces:
            SettingsPane(id, title: String(localized: "Spaces", table: "SafiraSettings", bundle: .module,
                                           comment: "Settings: pane title"),
                         subtitle: String(localized: "The current Profile’s Spaces, in the order of ⌃1 to ⌃9.",
                                          table: "SafiraSettings", bundle: .module,
                                          comment: "Settings: subtitle of the Spaces pane"),
                         systemImage: "square.stack.3d.up", tint: .purple)
        case .shortcuts:
            SettingsPane(id, title: String(localized: "Shortcuts", table: "SafiraSettings", bundle: .module,
                                           comment: "Settings: pane title"),
                         subtitle: String(localized: "The preset, and the keys of every command.", table: "SafiraSettings",
                                          bundle: .module, comment: "Settings: subtitle of the Shortcuts pane"),
                         systemImage: "keyboard", tint: .pink)
        case .defaults:
            SettingsPane(id, title: String(localized: "Defaults", table: "SafiraSettings", bundle: .module,
                                           comment: "Settings: pane title; every default Safira chose for the user"),
                         subtitle: String(localized: "Everything Safira decided for you, and where to change it.",
                                          table: "SafiraSettings", bundle: .module,
                                          comment: "Settings: subtitle of the Defaults pane"),
                         systemImage: "checklist", tint: .blue)
        case .linkRules:
            SettingsPane(id, title: String(localized: "Link Rules", table: "SafiraSettings", bundle: .module,
                                           comment: "Settings: pane title"),
                         subtitle: String(localized: "Where links from other apps open.", table: "SafiraSettings",
                                          bundle: .module, comment: "Settings: subtitle of the Link Rules pane"),
                         systemImage: "arrow.triangle.branch", tint: .indigo)
        case .sitePermissions:
            SettingsPane(id, title: String(localized: "Site Permissions", table: "SafiraSettings", bundle: .module,
                                           comment: "Settings: pane title"),
                         subtitle: String(localized: "What sites of the current Profile may use.", table: "SafiraSettings",
                                          bundle: .module, comment: "Settings: subtitle of the Site Permissions pane"),
                         systemImage: "hand.raised.fill", tint: .green)
        case .extensions:
            SettingsPane(id, title: String(localized: "Extensions", table: "SafiraSettings", bundle: .module,
                                           comment: "Settings: pane title"),
                         subtitle: String(localized: "Installed once, switched on per Profile.", table: "SafiraSettings",
                                          bundle: .module, comment: "Settings: subtitle of the Extensions pane"),
                         systemImage: "puzzlepiece.extension", tint: .orange)
        case .debug:
            SettingsPane(id, title: String(localized: "Debug", table: "SafiraSettings", bundle: .module,
                                           comment: "Settings: pane title"),
                         subtitle: String(localized: "Local logs to attach to a report.", table: "SafiraSettings",
                                          bundle: .module, comment: "Settings: subtitle of the Debug pane"),
                         systemImage: "ladybug", tint: .teal)
        }
    }
}

/// The Settings window's state for the app's life: the open pane, and how a menu item opens the window on its pane.
/// `present` shows the window; it belongs to the app.
@MainActor
public final class SettingsPresenter {
    public let model: SettingsShellModel<SettingsPaneID>
    private let present: @MainActor () -> Void

    public init(store: any KeyValueStore = UserDefaults.standard, present: @escaping @MainActor () -> Void) {
        model = SettingsShellModel(panes: SafiraSettings.panes, storageKey: SafiraSettings.storageKey, store: store)
        self.present = present
    }

    public func open(_ opener: SettingsOpener) {
        if let pane = opener.pane { model.open(pane: pane) }
        present()
    }

    public func open(pane: SettingsPaneID) {
        model.open(pane: pane)
        present()
    }
}
