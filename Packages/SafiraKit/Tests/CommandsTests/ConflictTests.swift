// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
import Commands
import Testing

private func recording(_ shortcut: Shortcut, for command: CommandID, on preset: ShortcutPreset? = nil) throws(ShortcutBindingError<CommandID>) -> ShortcutBindings<CommandID> {
    var changed = bindings(preset)
    try changed.record(shortcut, for: command, rules: SafiraShortcuts.rules)
    return changed
}

/// CommandKit refuses a key another command has, where Safira used to accept it and report the conflict.
@MainActor
@Test func aKeyAnotherCommandHasIsRefused() {
    #expect(throws: ShortcutBindingError<CommandID>.taken(Shortcut("t"), by: .newTab)) {
        try recording(Shortcut("t"), for: .reload)
    }
    #expect(throws: ShortcutBindingError<CommandID>.taken(Shortcut("l"), by: .openCommandBar)) {
        try recording(Shortcut("l"), for: .reload, on: .safari)
    }
}

@MainActor
@Test func aFixedMenuItemKeyIsRefused() {
    #expect(throws: ShortcutBindingError<CommandID>.reserved(Shortcut("c"))) {
        try recording(Shortcut("c"), for: .reload)
    }
    #expect(throws: ShortcutBindingError<CommandID>.reserved(Shortcut("h", [.command, .option]))) {
        try recording(Shortcut("h", [.command, .option]), for: .reload)
    }
}

@MainActor
@Test func tabAndEscapeAreRefusedWhateverTheirModifiers() {
    #expect(throws: ShortcutBindingError<CommandID>.reserved(Shortcut(Shortcut.tab, []))) {
        try recording(Shortcut(Shortcut.tab, []), for: .focusTabList)
    }
    #expect(throws: ShortcutBindingError<CommandID>.reserved(Shortcut(Shortcut.escape, [.command]))) {
        try recording(Shortcut(Shortcut.escape, [.command]), for: .focusTabList)
    }
}

/// A key without ⌘ or ⌃ types text in a page or the Command bar, which the menu would take; ⌥ alone types too.
@MainActor
@Test func aKeyWithoutCommandOrControlIsRefused() {
    #expect(throws: ShortcutBindingError<CommandID>.typesText(Shortcut("j", []))) {
        try recording(Shortcut("j", []), for: .reload)
    }
    #expect(throws: ShortcutBindingError<CommandID>.typesText(Shortcut("j", [.option]))) {
        try recording(Shortcut("j", [.option]), for: .reload)
    }
}

@MainActor
@Test func aKeyThatEditsTextIsRefused() {
    #expect(throws: ShortcutBindingError<CommandID>.editsText(Shortcut(Shortcut.leftArrow, [.command]))) {
        try recording(Shortcut(Shortcut.leftArrow, [.command]), for: .goBack)
    }
    #expect(throws: ShortcutBindingError<CommandID>.editsText(Shortcut(Shortcut.delete, [.command]))) {
        try recording(Shortcut(Shortcut.delete, [.command]), for: .clearBrowsingData)
    }
}

@Test func aControlCommandArrowAndShiftCommandDeleteCanBeRecorded() throws {
    let spaces = try recording(Shortcut(Shortcut.downArrow, [.control, .command]), for: .moveSpaceLeft)
    #expect(spaces.shortcut(.moveSpaceLeft)?.symbols == "⌃⌘↓")
    var changed = bindings(nil)
    try changed.unbind(.clearBrowsingData, rules: SafiraShortcuts.rules)
    try changed.record(Shortcut(Shortcut.delete, [.option, .command]), for: .clearBrowsingData, rules: SafiraShortcuts.rules)
    #expect(changed.shortcut(.clearBrowsingData)?.symbols == "⌥⌘⌫")
}

@MainActor
@Test func differentModifiersAreNotAConflict() throws {
    let changed = try recording(Shortcut("t", [.command, .option]), for: .reload)
    #expect(changed.conflicts == [])
    #expect(changed.keys(.reload).map(\.symbols) == ["⌥⌘T"])
}

/// Changes stored against another version of a set can still share a key; the Shortcuts window shows them.
@MainActor
@Test func storedChangesThatShareAKeyAreReported() {
    let clashing = ShortcutBindings(set: SafiraShortcuts.set(.safari), overrides: [.reload: [Shortcut("l")]])
    #expect(clashing.conflicts == [ShortcutConflict(shortcut: Shortcut("l"), commands: [.openCommandBar, .reload])])
}

@MainActor
@Test func unbindingACommandRemovesItsConflict() {
    let controller = ShortcutController(store: ShortcutStore(store: storeHolding(#"{"base":"safari","overrides":{"reload":["⌘L"]}}"#)),
                                        unreadable: { _ in })
    #expect(controller.conflicts.map(\.commands) == [[.openCommandBar, .reload]])
    controller.unbind(.reload)
    #expect(controller.conflicts == [])
}
