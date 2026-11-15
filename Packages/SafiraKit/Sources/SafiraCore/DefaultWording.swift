// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// The words several entries of the registry of defaults share, translated once.
public enum DefaultWording {
    public static func onOff(_ isOn: Bool) -> String {
        isOn ? String(localized: "On", table: "SafiraCore", bundle: .module, comment: "Defaults: the value of a switch that is on")
            : String(localized: "Off", table: "SafiraCore", bundle: .module, comment: "Defaults: the value of a switch that is off")
    }

    /// A pane of the Settings window, named as its sidebar names it (a test holds the two together).
    public enum SettingsPane: CaseIterable, Sendable {
        case general, shortcuts, defaults, linkRules, sitePermissions, debug
    }

    /// Where to change a default that has a place in the Settings window: “Settings › Link Rules”.
    public static func settings(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: String(localized: "Settings › General", table: "SafiraCore", bundle: .module,
                               comment: "Defaults: where to change a default; the Settings window and its pane")
        case .shortcuts: String(localized: "Settings › Shortcuts", table: "SafiraCore", bundle: .module,
                                 comment: "Defaults: where to change a default; the Settings window and its pane")
        case .defaults: String(localized: "Settings › Defaults", table: "SafiraCore", bundle: .module,
                                comment: "Defaults: where to change a default; the Settings window and its pane")
        case .linkRules: String(localized: "Settings › Link Rules", table: "SafiraCore", bundle: .module,
                                 comment: "Defaults: where to change a default; the Settings window and its pane")
        case .sitePermissions: String(localized: "Settings › Site Permissions", table: "SafiraCore", bundle: .module,
                                       comment: "Defaults: where to change a default; the Settings window and its pane")
        case .debug: String(localized: "Settings › Debug", table: "SafiraCore", bundle: .module,
                             comment: "Defaults: where to change a default; the Settings window and its pane")
        }
    }

    public static let viewMenu = String(localized: "View menu", table: "SafiraCore", bundle: .module,
                                        comment: "Defaults: where to change a default")
}
