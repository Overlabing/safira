// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Testing

private func press(_ characters: String, _ modifiers: ShortcutModifiers) -> KeyStroke {
    KeyStroke(characters: characters, modifiers: modifiers)
}

private let reservedPresses: [KeyStroke] = [
    press("t", .command), press("n", .command), press("w", .command), press("T", [.command, .shift]),
    press("l", .command), press("q", .command),
]

private let unreservedPresses: [KeyStroke] = [
    press("r", .command), press("t", []), press("t", .control), press("t", [.command, .option]),
    press("t", [.command, .control]), press("W", [.command, .shift]), press("a", .command), press("x", .command),
    press("[", .command), press("\u{F700}", [.command, .option]), press("\t", []), press("", .command),
]

/// The key equivalents the window offers to the menu before a web page sees them (standing order 22). ⌘N has no menu
/// item yet, so the menu will decline it, but it is reserved all the same.
@Test(arguments: reservedPresses)
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

@Test func theRegistryMarksExactlyTheSixReservedCommands() {
    let reserved = CommandRegistry.commands.filter(\.isReserved).map(\.id)
    #expect(Set(reserved) == [.newTab, .newWindow, .closeTab, .reopenClosedTab, .openCommandBar, .quit])
}
