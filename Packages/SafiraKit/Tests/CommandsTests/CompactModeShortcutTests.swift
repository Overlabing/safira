// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
import Commands
import Testing

/// ⌘B shows or hides the sidebar (Compact mode) in Safira's own shortcuts and in every preset, as the menu key, with the
/// key the browser documents kept beside it.
@Test(arguments: [nil] + ShortcutPreset.allCases.map(Optional.some))
func commandBTogglesCompactModeInEveryPreset(preset: ShortcutPreset?) {
    let name = String(describing: preset)
    #expect(menuKey(preset, .compactMode) == "⌘B", "\(name)")
    #expect(bindings(preset).owner(of: Shortcut("b")) == .compactMode, "\(name)")
    #expect(bindings(preset).owner(of: Shortcut("b"), other: .compactMode) == nil, "\(name)")
    #expect(SafiraShortcuts.set(preset).own[.compactMode]?.first?.from == "Safira default (Antonin, 2026-11-15)", "\(name)")
}

@Test func theKeyEachBrowserDocumentsStillTogglesCompactMode() {
    #expect(bindings(nil).keys(.compactMode).map(\.symbols) == ["⌘B", "⌃⌘S"])
    #expect(bindings(.zen).keys(.compactMode).map(\.symbols) == ["⌘B", "⌥⌘C"])
    #expect(bindings(.arc).keys(.compactMode).map(\.symbols) == ["⌘B", "⌘S"])
    #expect(bindings(.safari).keys(.compactMode).map(\.symbols) == ["⌘B"])
    for preset in [nil, .zen, .arc] as [ShortcutPreset?] {
        let second = bindings(preset).keys(.compactMode)[1]
        let aliases = SafiraShortcuts.menuAliases(bindings(preset)).filter { $0.command == .compactMode }
        #expect(aliases.map(\.shortcut) == [second], "\(String(describing: preset))")
    }
    #expect(SafiraShortcuts.menuAliases(bindings(.safari)).filter { $0.command == .compactMode }.isEmpty)
}

@Test func commandBCanBeRebound() throws {
    var changed = bindings(.zen)
    try changed.record(Shortcut("j", [.command, .option]), for: .compactMode, rules: SafiraShortcuts.rules)
    #expect(changed.shortcut(.compactMode)?.symbols == "⌥⌘J")
    try changed.unbind(.compactMode, rules: SafiraShortcuts.rules)
    #expect(changed.keys(.compactMode) == [])
    #expect(changed.owner(of: Shortcut("b")) == nil)
}
