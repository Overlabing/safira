// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// Every command a shortcut can be bound to. The raw value is the key used in preset files and in the saved overrides,
/// so it never changes once shipped.
public enum CommandID: String, CaseIterable, Hashable, Sendable {
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

    private static func numbered(_ raw: String, _ prefix: String) -> Int? {
        guard raw.hasPrefix(prefix) else { return nil }
        return Int(raw.dropFirst(prefix.count))
    }
}

/// Where a shortcut is heard. A window shortcut works whatever has the keyboard focus (it is a menu key equivalent);
/// a Command bar shortcut only while the Command bar has it.
public enum CommandScope: Hashable, Sendable {
    case window
    case commandBar
}

public struct Command: Hashable, Sendable, Identifiable {
    public let id: CommandID
    public let title: String
    public let scope: CommandScope
    /// The shortcut Safira ships with until a preset is chosen: the product defaults decided so far (⌘T ⌘N ⌘W ⇧⌘T ⌘L
    /// ⌘Q ⇧⌘[ ⇧⌘] reach the menu; Move Tab is ⌥⌘↑ and ⌥⌘↓; Tab and ⇧Tab leave the Command bar for the sidebar; Compact
    /// Mode is ⌃⌘S, the system's sidebar shortcut, and Show Sidebar is ⌥⌘S).
    public let defaultShortcut: Shortcut?
    /// The browser-level shortcuts that must always reach the menu, never the page, so the window offers them to the
    /// menu before the web view sees them.
    public let isReserved: Bool
    /// False when the key is handled by a fixed responder-chain rule rather than a menu item: the user sees the
    /// shortcut, but cannot change it yet.
    public let isRebindable: Bool
    /// False for a command with no behaviour behind it yet. It stays in the registry so its shortcut stays reserved.
    public let isImplemented: Bool
}

/// The registry: one entry per command, declared once. Menus, presets, overrides and the settings read it.
public enum CommandRegistry {
    public static let commands: [Command] = [
        window(.newTab, String(localized: "New Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("t"), .command), reserved: true),
        window(.newWindow, String(localized: "New Window", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("n"), .command), reserved: true, implemented: false),
        window(.newPrivateWindow, String(localized: "New Private Window", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("n"), [.command, .shift])),
        window(.closeTab, String(localized: "Close Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("w"), .command), reserved: true),
        window(.closeWindow, String(localized: "Close Window", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("w"), [.command, .shift])),
        window(.reopenClosedTab, String(localized: "Reopen Closed Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("t"), [.command, .shift]), reserved: true),
        window(.quit, String(localized: "Quit Safira", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("q"), .command), reserved: true),
        window(.openCommandBar, String(localized: "Open Command Bar", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("l"), .command), reserved: true),
        window(.focusTabList, String(localized: "Focus Tab List", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               nil),
        window(.compactMode, String(localized: "Compact Mode", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("s"), [.command, .control])),
        window(.showSidebar, String(localized: "Show Sidebar", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("s"), [.command, .option])),
        window(.reload, String(localized: "Reload Page", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("r"), .command)),
        window(.goBack, String(localized: "Back", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("["), .command)),
        window(.goForward, String(localized: "Forward", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("]"), .command)),
        window(.previousTab, String(localized: "Show Previous Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("["), [.command, .shift]), reserved: true),
        window(.nextTab, String(localized: "Show Next Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("]"), [.command, .shift]), reserved: true),
        window(.moveTabUp, String(localized: "Move Tab Up", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.up, [.command, .option])),
        window(.moveTabDown, String(localized: "Move Tab Down", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.down, [.command, .option])),
        // ⌃⌘ with N or an arrow: no browser-level, preset-default or system shortcut uses it.
        window(.newSpace, String(localized: "New Space…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("n"), [.command, .control])),
        window(.renameSpace, String(localized: "Rename Space…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               nil),
        window(.deleteSpace, String(localized: "Delete Space…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               nil),
        window(.previousSpace, String(localized: "Show Previous Space", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.left, [.command, .control])),
        window(.nextSpace, String(localized: "Show Next Space", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.right, [.command, .control])),
        window(.moveSpaceLeft, String(localized: "Move Space Left", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               nil),
        window(.moveSpaceRight, String(localized: "Move Space Right", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               nil),
        window(.togglePin, String(localized: "Pin or Unpin Tab", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               nil),
        window(.newFolder, String(localized: "New Folder…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               nil),
        // ⌃⌥⌘ with an arrow: distinct from the Space keys (⌃⌘ and an arrow), so a Profile never changes by accident.
        window(.newProfile, String(localized: "New Profile…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               nil),
        window(.renameProfile, String(localized: "Rename Profile…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               nil),
        window(.deleteProfile, String(localized: "Delete Profile…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               nil),
        window(.sitePermissions, String(localized: "Site Permissions…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               nil),
        // ⌥⌘L is Safari's own key for its download list; no other command or preset binding uses it.
        window(.showDownloads, String(localized: "Downloads", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.character("l"), [.command, .option])),
        window(.previousProfile, String(localized: "Show Previous Profile", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.left, [.command, .control, .option])),
        window(.nextProfile, String(localized: "Show Next Profile", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.right, [.command, .control, .option])),
        window(.clearBrowsingData, String(localized: "Clear History and Website Data…", table: "Commands", bundle: .module, comment: "Command: menu item and Shortcuts row"),
               Shortcut(.delete, [.command, .shift])),
        // ⌘1…⌘9 are Safari's and Firefox's tab keys; ⌃1…⌃9 are Arc's Space keys, and no other command uses them.
    ] + CommandID.selectTabCommands.enumerated().map { index, id in
        window(id, String(localized: "Show Tab \(index + 1)", table: "Commands", bundle: .module, comment: "Command name; the Tab's number from 1 to 9"),
               Shortcut(.character(Character("\(index + 1)")), .command))
    } + CommandID.selectSpaceCommands.enumerated().map { index, id in
        window(id, String(localized: "Show Space \(index + 1)", table: "Commands", bundle: .module, comment: "Command name; the Space's number from 1 to 9"),
               Shortcut(.character(Character("\(index + 1)")), .control))
    } + [
        Command(id: .commandBarNext, title: String(localized: "Command Bar: Move to the Tab List", table: "Commands", bundle: .module,
                                       comment: "Command name in the Shortcuts window; Tab moves from the Command bar"),
                scope: .commandBar,
                defaultShortcut: Shortcut(.tab), isReserved: false, isRebindable: false, isImplemented: true),
        Command(id: .commandBarPrevious, title: String(localized: "Command Bar: Move to the Tab List, Backward", table: "Commands", bundle: .module,
                                       comment: "Command name in the Shortcuts window; Tab moves from the Command bar"),
                scope: .commandBar,
                defaultShortcut: Shortcut(.tab, .shift), isReserved: false, isRebindable: false, isImplemented: true),
    ]

    public static func command(_ id: CommandID) -> Command {
        guard let command = commands.first(where: { $0.id == id }) else {
            preconditionFailure("\(id) is missing from the registry")
        }
        return command
    }

    /// Menu items that are not commands: the standard editing and window keys, which no preset or override can take.
    public static let fixedItems: [(title: String, shortcut: Shortcut)] = [
        (String(localized: "Cut", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut(.character("x"), .command)),
        (String(localized: "Copy", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut(.character("c"), .command)),
        (String(localized: "Paste", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut(.character("v"), .command)),
        (String(localized: "Select All", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut(.character("a"), .command)),
        (String(localized: "Minimize", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut(.character("m"), .command)),
        (String(localized: "Hide Safira", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut(.character("h"), .command)),
        (String(localized: "Hide Others", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut(.character("h"), [.command, .option])),
    ]

    private static func window(_ id: CommandID, _ title: String, _ shortcut: Shortcut?, reserved: Bool = false,
                               implemented: Bool = true) -> Command {
        Command(id: id, title: title, scope: .window, defaultShortcut: shortcut, isReserved: reserved,
                isRebindable: true, isImplemented: implemented)
    }
}
