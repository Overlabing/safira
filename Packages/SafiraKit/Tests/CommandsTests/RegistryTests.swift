// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Testing

@Test func everyCommandIsInTheRegistryOnce() {
    #expect(CommandRegistry.commands.map(\.id).sorted { $0.rawValue < $1.rawValue }
        == CommandID.allCases.sorted { $0.rawValue < $1.rawValue })
    #expect(Set(CommandRegistry.commands.map(\.title)).count == CommandRegistry.commands.count)
}

@Test func theDefaultsAreTheProductDefaultsDecidedSoFar() {
    func display(_ id: CommandID) -> String? { CommandRegistry.command(id).defaultShortcut?.display }
    #expect(display(.newTab) == "⌘T")
    #expect(display(.newWindow) == "⌘N")
    #expect(display(.closeTab) == "⌘W")
    #expect(display(.reopenClosedTab) == "⇧⌘T")
    #expect(display(.openCommandBar) == "⌘L")
    #expect(display(.quit) == "⌘Q")
    #expect(display(.moveTabUp) == "⌥⌘↑")
    #expect(display(.moveTabDown) == "⌥⌘↓")
    #expect(display(.commandBarNext) == "⇥")
    #expect(display(.commandBarPrevious) == "⇧⇥")
    #expect(KeyBindings.defaults.conflicts == [])
}

@Test func theCommandBarKeysAreFixedAndHearOnlyTheCommandBar() {
    for id in [CommandID.commandBarNext, .commandBarPrevious] {
        let command = CommandRegistry.command(id)
        #expect(command.scope == .commandBar)
        #expect(!command.isRebindable)
    }
}

@Test func aFixedCommandIgnoresPresetsAndOverrides() {
    var configuration = ShortcutConfiguration(preset: .arc)
    configuration.overrides[.commandBarNext] = .unbound
    #expect(configuration.bindings[.commandBarNext]?.display == "⇥")
}
