// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Testing

@Test func twoWindowCommandsOnTheSameShortcutAreReported() {
    var bindings = KeyBindings.defaults
    bindings[.reload] = Shortcut(.character("t"), .command)
    #expect(bindings.conflicts == [
        ShortcutConflict(shortcut: Shortcut(.character("t"), .command), commands: [.newTab, .reload], fixedItems: []),
    ])
}

@Test func aCommandOnAFixedMenuItemShortcutIsReported() {
    var bindings = KeyBindings.defaults
    bindings[.reload] = Shortcut(.character("c"), .command)
    #expect(bindings.conflicts == [
        ShortcutConflict(shortcut: Shortcut(.character("c"), .command), commands: [.reload], fixedItems: ["Copy"]),
    ])
}

@Test func aWindowShortcutOnACommandBarKeyIsReportedBecauseTheWindowHearsItToo() {
    var bindings = KeyBindings.defaults
    bindings[.focusTabList] = Shortcut(.tab)
    #expect(bindings.conflicts.map(\.shortcut) == [Shortcut(.tab)])
    #expect(bindings.conflicts.first?.commands == [.focusTabList, .commandBarNext])
}

@Test func differentModifiersAreNotAConflict() {
    var bindings = KeyBindings.defaults
    bindings[.reload] = Shortcut(.character("t"), [.command, .option])
    #expect(bindings.conflicts == [])
}

@Test func anOverrideThatClashesIsReportedByTheConfiguration() {
    var configuration = ShortcutConfiguration(preset: .safari)
    configuration.overrides[.reload] = .shortcut(Shortcut(.character("l"), .command))
    #expect(configuration.conflicts.map(\.commands) == [[.openCommandBar, .reload]])
}

@Test func unbindingACommandRemovesItsConflict() {
    var configuration = ShortcutConfiguration(preset: .safari)
    configuration.overrides[.reload] = .shortcut(Shortcut(.character("l"), .command))
    configuration.overrides[.reload] = .unbound
    #expect(configuration.conflicts == [])
}
