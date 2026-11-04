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
    #expect(display(.compactMode) == "⌃⌘S")
    #expect(display(.showSidebar) == "⌥⌘S")
    #expect(display(.previousTab) == "⇧⌘[")
    #expect(display(.nextTab) == "⇧⌘]")
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

@Test func theCompactModeCommandsAreWindowCommandsYouCanRebind() {
    for id in [CommandID.compactMode, .showSidebar] {
        let command = CommandRegistry.command(id)
        #expect(command.scope == .window)
        #expect(command.isRebindable)
        #expect(command.isImplemented)
        #expect(!command.isReserved)
    }
    #expect(CommandRegistry.command(.compactMode).title == "Compact Mode")
    #expect(CommandRegistry.command(.showSidebar).title == "Show Sidebar")
    #expect(CommandRegistry.commands.count == 26)
}

@Test func theSpaceCommandsAreRebindableWindowCommandsOnControlCommandKeys() {
    func display(_ id: CommandID) -> String? { CommandRegistry.command(id).defaultShortcut?.display }
    #expect(display(.newSpace) == "⌃⌘N")
    #expect(display(.previousSpace) == "⌃⌘←")
    #expect(display(.nextSpace) == "⌃⌘→")
    for id in [CommandID.renameSpace, .deleteSpace, .moveSpaceLeft, .moveSpaceRight] {
        #expect(display(id) == nil)
    }
    for id in [CommandID.newSpace, .renameSpace, .deleteSpace, .previousSpace, .nextSpace, .moveSpaceLeft, .moveSpaceRight] {
        let command = CommandRegistry.command(id)
        #expect(command.scope == .window)
        #expect(command.isRebindable)
        #expect(command.isImplemented)
        #expect(!command.isReserved)
    }
}

@Test func arcAndZenSwitchSpacesWithTheirOwnKeys() {
    func display(_ preset: ShortcutPreset, _ id: CommandID) -> String? {
        ShortcutConfiguration(preset: preset).bindings[id]?.display
    }
    #expect(display(.arc, .previousSpace) == "⌥⌘←")
    #expect(display(.arc, .nextSpace) == "⌥⌘→")
    #expect(display(.zen, .previousSpace) == "⌥⌘Q")
    #expect(display(.zen, .nextSpace) == "⌥⌘E")
    #expect(display(.safari, .nextSpace) == nil)
}
