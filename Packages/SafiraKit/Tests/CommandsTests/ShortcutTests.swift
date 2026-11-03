// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Testing

@Test func aShortcutRoundTripsThroughItsDataFileForm() throws {
    let shortcut = try #require(Shortcut(parsing: "command+shift+t"))
    #expect(shortcut == Shortcut(.character("t"), [.command, .shift]))
    #expect(shortcut.encoded == "shift+command+t")
    #expect(shortcut.display == "⇧⌘T")
    #expect(try #require(Shortcut(parsing: "Option+Command+Up")).display == "⌥⌘↑")
    #expect(try #require(Shortcut(parsing: "control+command+plus")).encoded == "control+command+plus")
    #expect(try #require(Shortcut(parsing: "tab")).display == "⇥")
}

@Test(arguments: ["", "command+", "command+shift", "t+t", "command+command+t", "hyper+t", "command+nonsense"])
func anUnreadableShortcutIsRejected(text: String) {
    #expect(Shortcut(parsing: text) == nil)
}

@Test func aMenuKeyEquivalentIsTheKeyAlone() {
    #expect(Shortcut(.character("t"), [.command, .shift]).menuKeyEquivalent == "t")
    #expect(Shortcut(.up, [.command, .option]).menuKeyEquivalent == "\u{F700}")
    #expect(Shortcut(.tab).menuKeyEquivalent == "\t")
}

@Test func aKeyStrokeNamesTheKeyNotTheSymbolItTypes() {
    #expect(KeyStroke(characters: "T", modifiers: [.command, .shift]).shortcut == Shortcut(.character("t"), [.command, .shift]))
    #expect(KeyStroke(characters: "{", modifiers: [.command, .shift]).shortcut == Shortcut(.character("["), [.command, .shift]))
    #expect(KeyStroke(characters: "\u{F701}", modifiers: [.command, .option]).shortcut == Shortcut(.down, [.command, .option]))
    #expect(KeyStroke(characters: "\t", modifiers: .shift).shortcut == Shortcut(.tab, .shift))
    #expect(KeyStroke(characters: "", modifiers: .command).shortcut == nil)
}
