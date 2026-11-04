// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// A shortcut that more than one thing claims.
public struct ShortcutConflict: Hashable, Sendable {
    public let shortcut: Shortcut
    public let commands: [CommandID]
    /// Titles of fixed menu items (Copy, Hide…) that already use the shortcut.
    public let fixedItems: [String]

    public init(shortcut: Shortcut, commands: [CommandID], fixedItems: [String]) {
        self.shortcut = shortcut
        self.commands = commands
        self.fixedItems = fixedItems
    }
}

/// The shortcut of each command once a preset and the user's overrides are applied. A command without an entry is unbound.
public struct KeyBindings: Hashable, Sendable {
    private var shortcuts: [CommandID: Shortcut]

    public init(_ shortcuts: [CommandID: Shortcut] = [:]) {
        self.shortcuts = shortcuts
    }

    public subscript(command: CommandID) -> Shortcut? {
        get { shortcuts[command] }
        set { shortcuts[command] = newValue }
    }

    /// The bindings of a Safira with no preset chosen.
    public static let defaults = KeyBindings(Dictionary(uniqueKeysWithValues: CommandRegistry.commands.compactMap { command in
        command.defaultShortcut.map { (command.id, $0) }
    }))

    /// Whether a key press must go to the menu before the focused view sees it: it is the shortcut of a reserved command.
    /// The window calls this from `performKeyEquivalent`; a web page that handles the key itself still loses.
    public func reservesKeyEquivalent(_ press: KeyStroke) -> Bool {
        guard let shortcut = press.shortcut else { return false }
        return CommandRegistry.commands.contains { $0.isReserved && $0.scope == .window && shortcuts[$0.id] == shortcut }
    }

    /// The window command bound to a shortcut.
    public func command(for shortcut: Shortcut) -> CommandID? {
        CommandRegistry.commands.first { $0.scope == .window && shortcuts[$0.id] == shortcut }?.id
    }

    /// Shortcuts claimed twice, by two commands that can hear the same key (a window command hears every key, a Command
    /// bar command only its own) or by a command and a fixed menu item. Sorted for a stable report.
    public var conflicts: [ShortcutConflict] {
        let commands = CommandRegistry.commands
        var found: [ShortcutConflict] = []
        for shortcut in Set(shortcuts.values) {
            let sharing = commands.filter { shortcuts[$0.id] == shortcut }
            let fixed = CommandRegistry.fixedItems.filter { $0.shortcut == shortcut }.map(\.title)
            let hearTheSameKey = sharing.count > 1 && (sharing.contains { $0.scope == .window } || Set(sharing.map(\.scope)).count == 1)
            if hearTheSameKey || !fixed.isEmpty {
                found.append(ShortcutConflict(shortcut: shortcut, commands: sharing.map(\.id), fixedItems: fixed))
            }
        }
        return found.sorted { $0.shortcut.encoded < $1.shortcut.encoded }
    }
}
