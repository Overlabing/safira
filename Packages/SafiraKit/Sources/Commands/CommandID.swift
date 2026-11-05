// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
import Foundation

/// Every command a shortcut can be bound to. The raw value names the command in the shortcut set files and in the
/// stored bindings, so it never changes once shipped; the order of the cases settles which command keeps a key bound
/// twice (CommandKit's `allCases` rule).
public enum CommandID: String, CommandIdentifier {
    case newTab, newWindow, newPrivateWindow, closeTab, closeWindow, reopenClosedTab, quit
    case openCommandBar, focusTabList, compactMode, showSidebar
    case reload, goBack, goForward
    case previousTab, nextTab, moveTabUp, moveTabDown
    case commandBarNext, commandBarPrevious
    case newSpace, renameSpace, deleteSpace, previousSpace, nextSpace, moveSpaceLeft, moveSpaceRight
    case togglePin, newFolder
    case newProfile, renameProfile, deleteProfile, previousProfile, nextProfile, sitePermissions
    case clearBrowsingData
    case showDownloads
    case selectTab1, selectTab2, selectTab3, selectTab4, selectTab5, selectTab6, selectTab7, selectTab8, selectTab9
    case selectSpace1, selectSpace2, selectSpace3, selectSpace4, selectSpace5, selectSpace6, selectSpace7, selectSpace8
    case selectSpace9

    /// ⌘1…⌘9 and ⌃1…⌃9: the Tab or Space a numbered command shows, 1 for the first.
    public var tabNumber: Int? { Self.numbered(rawValue, "selectTab") }
    public var spaceNumber: Int? { Self.numbered(rawValue, "selectSpace") }

    public static let selectTabCommands: [CommandID] = [
        .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
    ]
    public static let selectSpaceCommands: [CommandID] = [
        .selectSpace1, .selectSpace2, .selectSpace3, .selectSpace4, .selectSpace5, .selectSpace6, .selectSpace7,
        .selectSpace8, .selectSpace9,
    ]

    /// False for a command with no behaviour behind it yet. It keeps its shortcut, so that no other command takes it.
    public var isImplemented: Bool { self != .newWindow }

    /// The menu item's title, also the row of the Shortcuts window.
    public var title: String {
        if let number = tabNumber {
            return String(localized: "Show Tab \(number)", table: "Commands", bundle: .module, comment: "Command name; the Tab's number from 1 to 9")
        }
        if let number = spaceNumber {
            return String(localized: "Show Space \(number)", table: "Commands", bundle: .module, comment: "Command name; the Space's number from 1 to 9")
        }
        return switch self {
        case .newTab: String(localized: "New Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .newWindow: String(localized: "New Window", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .newPrivateWindow: String(localized: "New Private Window", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .closeTab: String(localized: "Close Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .closeWindow: String(localized: "Close Window", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .reopenClosedTab: String(localized: "Reopen Closed Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .quit: String(localized: "Quit Safira", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .openCommandBar: String(localized: "Open Command Bar", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .focusTabList: String(localized: "Focus Tab List", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .compactMode: String(localized: "Compact Mode", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .showSidebar: String(localized: "Show Sidebar", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .reload: String(localized: "Reload Page", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .goBack: String(localized: "Back", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .goForward: String(localized: "Forward", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .previousTab: String(localized: "Show Previous Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .nextTab: String(localized: "Show Next Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .moveTabUp: String(localized: "Move Tab Up", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .moveTabDown: String(localized: "Move Tab Down", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .commandBarNext:
            String(localized: "Command Bar: Move to the Tab List", table: "Commands", bundle: .module,
                   comment: "Command name in the Shortcuts window; Tab moves from the Command bar")
        case .commandBarPrevious:
            String(localized: "Command Bar: Move to the Tab List, Backward", table: "Commands", bundle: .module,
                   comment: "Command name in the Shortcuts window; Tab moves from the Command bar")
        case .newSpace: String(localized: "New Space…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .renameSpace: String(localized: "Rename Space…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .deleteSpace: String(localized: "Delete Space…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .previousSpace: String(localized: "Show Previous Space", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .nextSpace: String(localized: "Show Next Space", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .moveSpaceLeft: String(localized: "Move Space Left", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .moveSpaceRight: String(localized: "Move Space Right", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .togglePin: String(localized: "Pin or Unpin Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .newFolder: String(localized: "New Folder…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .newProfile: String(localized: "New Profile…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .renameProfile: String(localized: "Rename Profile…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .deleteProfile: String(localized: "Delete Profile…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .previousProfile: String(localized: "Show Previous Profile", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .nextProfile: String(localized: "Show Next Profile", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .sitePermissions: String(localized: "Site Permissions…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .clearBrowsingData:
            String(localized: "Clear History and Website Data…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .showDownloads: String(localized: "Downloads", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row")
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9,
             .selectSpace1, .selectSpace2, .selectSpace3, .selectSpace4, .selectSpace5, .selectSpace6, .selectSpace7,
             .selectSpace8, .selectSpace9:
            preconditionFailure("numbered commands are titled above")
        }
    }

    private static func numbered(_ raw: String, _ prefix: String) -> Int? {
        guard raw.hasPrefix(prefix) else { return nil }
        return Int(raw.dropFirst(prefix.count))
    }
}
