// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// The modifier keys of a shortcut. Caps Lock and the function key never take part in one.
public struct ShortcutModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let control = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let shift = ShortcutModifiers(rawValue: 1 << 2)
    public static let command = ShortcutModifiers(rawValue: 1 << 3)

    /// Ordered as macOS prints them: ⌃⌥⇧⌘.
    static let named: [(name: String, glyph: String, modifier: ShortcutModifiers)] = [
        ("control", "⌃", .control), ("option", "⌥", .option), ("shift", "⇧", .shift), ("command", "⌘", .command),
    ]
}

/// The key of a shortcut, independent of the modifiers held with it. Letters are lowercase.
public enum ShortcutKey: Hashable, Sendable {
    case character(Character)
    case up, down, left, right
    case tab, returnKey, escape, space, delete

    private static let names: [(name: String, key: ShortcutKey, glyph: String, menuCharacter: String)] = [
        ("up", .up, "↑", "\u{F700}"), ("down", .down, "↓", "\u{F701}"),
        ("left", .left, "←", "\u{F702}"), ("right", .right, "→", "\u{F703}"),
        ("tab", .tab, "⇥", "\t"), ("return", .returnKey, "↩", "\r"), ("escape", .escape, "⎋", "\u{1B}"),
        ("space", .space, "␣", " "), ("delete", .delete, "⌫", "\u{8}"),
    ]

    /// The keys that type a different symbol with Shift on a US keyboard: a shortcut names the key, not the symbol.
    private static let unshifted: [Character: Character] = [
        "{": "[", "}": "]", "<": ",", ">": ".", "?": "/", ":": ";", "\"": "'", "|": "\\", "~": "`", "_": "-", "+": "=",
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9", ")": "0",
    ]

    /// A key from its data-file name: "t", "[", "up", "tab". A plus sign is written "plus".
    init?(name: String) {
        if name == "plus" {
            self = .character("+")
        } else if let named = Self.names.first(where: { $0.name == name }) {
            self = named.key
        } else if name.count == 1, let character = name.first {
            self = .character(character)
        } else {
            return nil
        }
    }

    /// The key a typed character stands for, given whether Shift was held.
    init?(typed characters: String, shift: Bool) {
        if let named = Self.names.first(where: { $0.menuCharacter == characters }) {
            self = named.key
        } else if characters == "\u{7F}" {
            self = .delete
        } else if characters == "\u{3}" {
            self = .returnKey
        } else if characters.count == 1, let character = characters.lowercased().first {
            self = .character(shift ? Self.unshifted[character] ?? character : character)
        } else {
            return nil
        }
    }

    var name: String {
        if case .character(let character) = self { return character == "+" ? "plus" : String(character) }
        return Self.names.first { $0.key == self }?.name ?? ""
    }

    var glyph: String {
        if case .character(let character) = self { return character.uppercased() }
        return Self.names.first { $0.key == self }?.glyph ?? ""
    }

    /// The key equivalent an `NSMenuItem` takes for this key.
    var menuCharacter: String {
        if case .character(let character) = self { return String(character) }
        return Self.names.first { $0.key == self }?.menuCharacter ?? ""
    }
}

/// A key with its modifiers. Stored in data files as "command+shift+t" and shown as ⇧⌘T.
public struct Shortcut: Hashable, Sendable {
    public let key: ShortcutKey
    public let modifiers: ShortcutModifiers

    public init(_ key: ShortcutKey, _ modifiers: ShortcutModifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// Parses "command+shift+t"; nil when a part is unknown, a modifier repeats, or there is no key.
    public init?(parsing text: String) {
        var modifiers: ShortcutModifiers = []
        var key: ShortcutKey?
        for part in text.lowercased().split(separator: "+", omittingEmptySubsequences: false) {
            if let modifier = ShortcutModifiers.named.first(where: { $0.name == part }) {
                guard !modifiers.contains(modifier.modifier) else { return nil }
                modifiers.insert(modifier.modifier)
            } else if key == nil, let parsed = ShortcutKey(name: String(part)) {
                key = parsed
            } else {
                return nil
            }
        }
        guard let key else { return nil }
        self.init(key, modifiers)
    }

    /// The data-file form, the inverse of `init(parsing:)`.
    public var encoded: String {
        (ShortcutModifiers.named.filter { modifiers.contains($0.modifier) }.map(\.name) + [key.name])
            .joined(separator: "+")
    }

    /// The form macOS prints: modifiers in the order ⌃⌥⇧⌘, then the key.
    public var display: String {
        ShortcutModifiers.named.filter { modifiers.contains($0.modifier) }.map(\.glyph).joined() + key.glyph
    }

    /// The key equivalent for an `NSMenuItem`, whose modifier mask is `modifiers`.
    public var menuKeyEquivalent: String { key.menuCharacter }
}

/// A key press as the window receives it: the characters the key types ignoring modifiers other than Shift, and the
/// modifiers held. The App target fills it from an `NSEvent`; nothing here knows AppKit.
public struct KeyStroke: Hashable, Sendable {
    public let characters: String
    public let modifiers: ShortcutModifiers

    public init(characters: String, modifiers: ShortcutModifiers) {
        self.characters = characters
        self.modifiers = modifiers
    }

    /// The shortcut this press performs; nil for a press that is no key (a dead key, a modifier alone).
    public var shortcut: Shortcut? {
        ShortcutKey(typed: characters, shift: modifiers.contains(.shift)).map { Shortcut($0, modifiers) }
    }
}
