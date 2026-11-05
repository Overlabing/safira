// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
import Commands
import Testing

/// A key press as the window reads it: AppKit's characters, those with no modifier, and the modifiers held.
private func press(_ characters: String, _ base: String, _ modifiers: Set<Shortcut.Modifier>) -> Shortcut? {
    Shortcut(characters: characters, baseCharacters: base, modifiers: modifiers)
}

private func press(_ characters: String, _ modifiers: Set<Shortcut.Modifier>) -> Shortcut? {
    Shortcut(characters: characters, modifiers: modifiers)
}

private func takesFirst(_ bindings: ShortcutBindings<CommandID>, _ press: Shortcut?) -> Bool {
    press.map { bindings.takesKeyBeforeFocusedView($0, rules: SafiraShortcuts.rules) } ?? false
}

/// The six that every preset keeps.
private let reservedPresses: [Shortcut?] = [
    press("t", [.command]), press("n", [.command]), press("w", [.command]), press("T", "t", [.command, .shift]),
    press("l", [.command]), press("q", [.command]),
]

/// ⇧⌘[ and ⇧⌘] type "{" and "}" because Shift is held; the key is the one with no modifier.
private let tabSwitchingPresses: [Shortcut?] = [press("{", "[", [.command, .shift]), press("}", "]", [.command, .shift])]

private let unreservedPresses: [Shortcut?] = [
    press("r", [.command]), press("t", []), press("\u{14}", "t", [.control]), press("†", "t", [.command, .option]),
    press("\u{14}", "t", [.command, .control]), press("W", "w", [.command, .shift]), press("a", [.command]),
    press("x", [.command]), press("[", [.command]), press("{", "[", [.command]), press("}", "]", [.command]),
    press("\u{F700}", [.command, .option]), press("\t", []), press("", [.command]),
]

/// The key equivalents the window offers to the menu before a web page sees them (standing order 22). ⌘N has no menu
/// item yet, so the menu will decline it, but it is reserved all the same.
@Test(arguments: reservedPresses + tabSwitchingPresses)
func theBrowserLevelShortcutsAreReservedByDefault(key: Shortcut?) {
    #expect(takesFirst(bindings(nil), key))
}

@Test(arguments: unreservedPresses)
func otherKeysGoToThePage(key: Shortcut?) {
    #expect(!takesFirst(bindings(nil), key))
}

@Test func aShiftedLetterIsReservedOnlyForTheCommandsThatAskForShift() {
    #expect(!takesFirst(bindings(nil), press("N", "n", [.command, .shift])))
    #expect(takesFirst(bindings(nil), press("t", [.command])))
    #expect(takesFirst(bindings(nil), press("T", "t", [.command, .shift])))
}

@Test func theReservedKeysFollowTheBindingsOfTheReservedCommands() throws {
    var changed = bindings(nil)
    try changed.record(Shortcut("k"), for: .newTab, rules: SafiraShortcuts.rules)
    #expect(!takesFirst(changed, press("t", [.command])))
    #expect(takesFirst(changed, press("k", [.command])))
    try changed.unbind(.closeTab, rules: SafiraShortcuts.rules)
    #expect(!takesFirst(changed, press("w", [.command])))
}

@Test func aCommandThatIsNotReservedNeverReachesTheMenuFirst() throws {
    var changed = bindings(nil)
    try changed.record(Shortcut("j"), for: .reload, rules: SafiraShortcuts.rules)
    #expect(!takesFirst(changed, press("j", [.command])))
}

@Test(arguments: ShortcutPreset.allCases)
func everyPresetReservesTheSameBrowserShortcuts(preset: ShortcutPreset) {
    for key in reservedPresses {
        #expect(takesFirst(bindings(preset), key), "\(preset) \(key?.symbols ?? "")")
    }
}

@Test func theRulesReserveExactlyTheEightBrowserLevelCommands() {
    #expect(SafiraShortcuts.rules.beforeFocusedView
        == [.newTab, .newWindow, .closeTab, .reopenClosedTab, .openCommandBar, .quit, .previousTab, .nextTab])
}

@Test func theReservedShortcutsByDefaultAreTheseEightLiterally() {
    let shortcuts = SafiraShortcuts.rules.beforeFocusedView.compactMap { bindings(nil).shortcut($0)?.symbols }
    #expect(Set(shortcuts) == ["⌘T", "⌘N", "⌘W", "⇧⌘T", "⌘L", "⌘Q", "⇧⌘[", "⇧⌘]"])
    #expect(shortcuts.count == 8)
}

@Test func showingThePreviousAndNextTabIsReservedWhereverThePresetOrSafirasSetBindsIt() {
    for key in tabSwitchingPresses {
        #expect(takesFirst(bindings(.safari), key))
        #expect(takesFirst(bindings(.zen), key))
        #expect(!takesFirst(bindings(.arc), key))
    }
    #expect(takesFirst(bindings(.arc), press("\u{F700}", [.command, .option])))
    #expect(takesFirst(bindings(.arc), press("\u{F701}", [.command, .option])))
    #expect(!takesFirst(bindings(.zen), press("\u{F700}", [.command, .option])))
}
