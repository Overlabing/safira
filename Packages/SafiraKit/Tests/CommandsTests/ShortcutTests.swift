// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
import Testing

/// How the window reads a key press (`Shortcut(event:)` passes AppKit's `characters` and `characters(byApplyingModifiers: [])`).
@Test func aKeyPressNamesTheKeyNotTheSymbolItTypes() {
    #expect(Shortcut(characters: "T", baseCharacters: "t", modifiers: [.command, .shift]) == Shortcut("t", [.command, .shift]))
    #expect(Shortcut(characters: "{", baseCharacters: "[", modifiers: [.command, .shift]) == Shortcut("[", [.command, .shift]))
    #expect(Shortcut(characters: "\u{F701}", modifiers: [.command, .option]) == Shortcut(Shortcut.downArrow, [.command, .option]))
    #expect(Shortcut(characters: "", modifiers: [.command]) == nil)
}

@Test func aShortcutIsWrittenAsTheMenuWritesIt() {
    #expect(Shortcut("t", [.command, .shift]).symbols == "⇧⌘T")
    #expect(Shortcut(Shortcut.upArrow, [.command, .option]).symbols == "⌥⌘↑")
    #expect(Shortcut(Shortcut.tab, [.shift]).symbols == "⇧⇥")
    #expect(Shortcut(notation: "⌃⌥⌘←") == Shortcut(Shortcut.leftArrow, [.control, .option, .command]))
}
