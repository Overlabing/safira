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
        window(.newTab, "New Tab", Shortcut(.character("t"), .command), reserved: true),
        window(.newWindow, "New Window", Shortcut(.character("n"), .command), reserved: true, implemented: false),
        window(.newPrivateWindow, "New Private Window", Shortcut(.character("n"), [.command, .shift])),
        window(.closeTab, "Close Tab", Shortcut(.character("w"), .command), reserved: true),
        window(.closeWindow, "Close Window", Shortcut(.character("w"), [.command, .shift])),
        window(.reopenClosedTab, "Reopen Closed Tab", Shortcut(.character("t"), [.command, .shift]), reserved: true),
        window(.quit, "Quit Safira", Shortcut(.character("q"), .command), reserved: true),
        window(.openCommandBar, "Open Command Bar", Shortcut(.character("l"), .command), reserved: true),
        window(.focusTabList, "Focus Tab List", nil),
        window(.compactMode, "Compact Mode", Shortcut(.character("s"), [.command, .control])),
        window(.showSidebar, "Show Sidebar", Shortcut(.character("s"), [.command, .option])),
        window(.reload, "Reload Page", Shortcut(.character("r"), .command)),
        window(.goBack, "Back", Shortcut(.character("["), .command)),
        window(.goForward, "Forward", Shortcut(.character("]"), .command)),
        window(.previousTab, "Show Previous Tab", Shortcut(.character("["), [.command, .shift]), reserved: true),
        window(.nextTab, "Show Next Tab", Shortcut(.character("]"), [.command, .shift]), reserved: true),
        window(.moveTabUp, "Move Tab Up", Shortcut(.up, [.command, .option])),
        window(.moveTabDown, "Move Tab Down", Shortcut(.down, [.command, .option])),
        // ⌃⌘ with N or an arrow: no browser-level, preset-default or system shortcut uses it.
        window(.newSpace, "New Space…", Shortcut(.character("n"), [.command, .control])),
        window(.renameSpace, "Rename Space…", nil),
        window(.deleteSpace, "Delete Space…", nil),
        window(.previousSpace, "Show Previous Space", Shortcut(.left, [.command, .control])),
        window(.nextSpace, "Show Next Space", Shortcut(.right, [.command, .control])),
        window(.moveSpaceLeft, "Move Space Left", nil),
        window(.moveSpaceRight, "Move Space Right", nil),
        window(.togglePin, "Pin or Unpin Tab", nil),
        window(.newFolder, "New Folder…", nil),
        // ⌃⌥⌘ with an arrow: distinct from the Space keys (⌃⌘ and an arrow), so a Profile never changes by accident.
        window(.newProfile, "New Profile…", nil),
        window(.renameProfile, "Rename Profile…", nil),
        window(.deleteProfile, "Delete Profile…", nil),
        window(.sitePermissions, "Site Permissions…", nil),
        window(.previousProfile, "Show Previous Profile", Shortcut(.left, [.command, .control, .option])),
        window(.nextProfile, "Show Next Profile", Shortcut(.right, [.command, .control, .option])),
        Command(id: .commandBarNext, title: "Command Bar: Move to the Tab List", scope: .commandBar,
                defaultShortcut: Shortcut(.tab), isReserved: false, isRebindable: false, isImplemented: true),
        Command(id: .commandBarPrevious, title: "Command Bar: Move to the Tab List, Backward", scope: .commandBar,
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
        ("Cut", Shortcut(.character("x"), .command)),
        ("Copy", Shortcut(.character("c"), .command)),
        ("Paste", Shortcut(.character("v"), .command)),
        ("Select All", Shortcut(.character("a"), .command)),
        ("Minimize", Shortcut(.character("m"), .command)),
        ("Hide Safira", Shortcut(.character("h"), .command)),
        ("Hide Others", Shortcut(.character("h"), [.command, .option])),
    ]

    private static func window(_ id: CommandID, _ title: String, _ shortcut: Shortcut?, reserved: Bool = false,
                               implemented: Bool = true) -> Command {
        Command(id: id, title: title, scope: .window, defaultShortcut: shortcut, isReserved: reserved,
                isRebindable: true, isImplemented: implemented)
    }
}
