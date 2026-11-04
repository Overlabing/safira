// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Testing

private func press(_ characters: String, _ modifiers: ShortcutModifiers) -> KeyStroke {
    KeyStroke(characters: characters, modifiers: modifiers)
}

/// The six that every preset keeps.
private let reservedPresses: [KeyStroke] = [
    press("t", .command), press("n", .command), press("w", .command), press("T", [.command, .shift]),
    press("l", .command), press("q", .command),
]

/// ⇧⌘[ and ⇧⌘] arrive as "{" and "}" because Shift is held.
private let tabSwitchingPresses: [KeyStroke] = [press("{", [.command, .shift]), press("}", [.command, .shift])]

private let unreservedPresses: [KeyStroke] = [
    press("r", .command), press("t", []), press("t", .control), press("t", [.command, .option]),
    press("t", [.command, .control]), press("W", [.command, .shift]), press("a", .command), press("x", .command),
    press("[", .command), press("{", .command), press("}", .command), press("\u{F700}", [.command, .option]),
    press("\t", []), press("", .command),
]

/// The key equivalents the window offers to the menu before a web page sees them (standing order 22). ⌘N has no menu
/// item yet, so the menu will decline it, but it is reserved all the same.
@Test(arguments: reservedPresses + tabSwitchingPresses)
func theBrowserLevelShortcutsAreReservedByDefault(key: KeyStroke) {
    #expect(KeyBindings.defaults.reservesKeyEquivalent(key))
}

@Test(arguments: unreservedPresses)
func otherKeysGoToThePage(key: KeyStroke) {
    #expect(!KeyBindings.defaults.reservesKeyEquivalent(key))
}

@Test func aShiftedLetterIsReservedOnlyForTheCommandsThatAskForShift() {
    // ⇧⌘N is not ⌘N; ⌘T is not ⇧⌘T.
    #expect(!KeyBindings.defaults.reservesKeyEquivalent(press("N", [.command, .shift])))
    #expect(KeyBindings.defaults.reservesKeyEquivalent(press("t", .command)))
    #expect(KeyBindings.defaults.reservesKeyEquivalent(press("T", [.command, .shift])))
}

@Test func theReservedKeysFollowTheBindingsOfTheReservedCommands() {
    var bindings = KeyBindings.defaults
    bindings[.newTab] = Shortcut(.character("k"), .command)
    #expect(!bindings.reservesKeyEquivalent(press("t", .command)))
    #expect(bindings.reservesKeyEquivalent(press("k", .command)))
    bindings[.closeTab] = nil
    #expect(!bindings.reservesKeyEquivalent(press("w", .command)))
}

@Test func aCommandThatIsNotReservedNeverReachesTheMenuFirst() {
    var bindings = KeyBindings.defaults
    bindings[.reload] = Shortcut(.character("j"), .command)
    #expect(!bindings.reservesKeyEquivalent(press("j", .command)))
}

@Test(arguments: ShortcutPreset.allCases)
func everyPresetReservesTheSameBrowserShortcuts(preset: ShortcutPreset) {
    let bindings = ShortcutConfiguration(preset: preset).bindings
    for key in reservedPresses {
        #expect(bindings.reservesKeyEquivalent(key), "\(preset) \(key.characters)")
    }
}

@Test func theRegistryMarksExactlyTheEightReservedCommands() {
    let reserved = CommandRegistry.commands.filter(\.isReserved).map(\.id)
    #expect(Set(reserved) == [.newTab, .newWindow, .closeTab, .reopenClosedTab, .openCommandBar, .quit, .previousTab, .nextTab])
}

@Test func theReservedShortcutsByDefaultAreTheseEightLiterally() {
    let shortcuts = CommandRegistry.commands.filter(\.isReserved).compactMap { $0.defaultShortcut?.display }
    #expect(Set(shortcuts) == ["⌘T", "⌘N", "⌘W", "⇧⌘T", "⌘L", "⌘Q", "⇧⌘[", "⇧⌘]"])
    #expect(shortcuts.count == 8)
}

@Test func showingThePreviousAndNextTabIsReservedWhereverThePresetBindsIt() {
    func reserves(_ preset: ShortcutPreset, _ key: KeyStroke) -> Bool {
        ShortcutConfiguration(preset: preset).bindings.reservesKeyEquivalent(key)
    }
    for key in tabSwitchingPresses {
        #expect(reserves(.safari, key))
        #expect(!reserves(.zen, key))
        #expect(!reserves(.arc, key))
    }
    #expect(reserves(.arc, press("\u{F700}", [.command, .option])))
    #expect(reserves(.arc, press("\u{F701}", [.command, .option])))
    #expect(!reserves(.zen, press("\u{F700}", [.command, .option])))
}
