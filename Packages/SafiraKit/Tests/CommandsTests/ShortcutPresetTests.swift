// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Foundation
import Testing

@Test func thePresetsAreZenArcAndSafari() {
    #expect(ShortcutPreset.allCases.map(\.rawValue) == ["zen", "arc", "safari"])
}

@Test(arguments: ShortcutPreset.allCases)
func aPresetCitesAnHttpsSourceAndAnIsoCheckDate(preset: ShortcutPreset) throws {
    let data = preset.data
    #expect(data.preset == preset)
    #expect(data.source.scheme == "https")
    #expect(data.checked.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil)
    #expect(!data.name.isEmpty)
}

@Test(arguments: ShortcutPreset.allCases)
func aPresetBindsOrExplainsEveryRebindableCommand(preset: ShortcutPreset) {
    let data = preset.data
    for command in CommandRegistry.commands where command.isRebindable {
        let bound = data.bindings[command.id] != nil
        let explained = !(data.unbound[command.id] ?? "").isEmpty
        #expect(bound != explained, "\(preset) must either bind or explain \(command.id), not both nor neither")
    }
    for id in data.bindings.keys + Array(data.unbound.keys) {
        #expect(CommandRegistry.command(id).isRebindable)
    }
}

@Test(arguments: ShortcutPreset.allCases)
func aPresetSaysWhereEachShortcutComesFrom(preset: ShortcutPreset) {
    for (id, binding) in preset.data.bindings {
        #expect(!binding.from.isEmpty, "\(preset) \(id)")
    }
}

@Test(arguments: ShortcutPreset.allCases)
func aPresetHasNoConflict(preset: ShortcutPreset) {
    #expect(ShortcutConfiguration(preset: preset).conflicts == [])
}

@Test func zenArcAndSafariKeepTheBrowserShortcutsInTheMenu() {
    for preset in ShortcutPreset.allCases {
        let bindings = ShortcutConfiguration(preset: preset).bindings
        #expect(bindings[.newTab]?.display == "⌘T", "\(preset)")
        #expect(bindings[.newWindow]?.display == "⌘N", "\(preset)")
        #expect(bindings[.closeTab]?.display == "⌘W", "\(preset)")
        #expect(bindings[.reopenClosedTab]?.display == "⇧⌘T", "\(preset)")
        #expect(bindings[.openCommandBar]?.display == "⌘L", "\(preset)")
        #expect(bindings[.quit]?.display == "⌘Q", "\(preset)")
    }
}

@Test func thePresetsDifferWhereTheBrowsersDo() {
    func display(_ preset: ShortcutPreset, _ id: CommandID) -> String? {
        ShortcutConfiguration(preset: preset).bindings[id]?.display
    }
    #expect(display(.arc, .previousTab) == "⌥⌘↑")
    #expect(display(.arc, .nextTab) == "⌥⌘↓")
    #expect(display(.safari, .previousTab) == "⇧⌘[")
    #expect(display(.safari, .nextTab) == "⇧⌘]")
    #expect(display(.zen, .previousTab) == "⇧⌘[")
    #expect(display(.zen, .closeWindow) == "⇧⌘W")
}

@Test func aCommandWithNoEquivalentKeepsItsReasonAndTakesSafirasDefault() {
    #expect(ShortcutPreset.safari.data.unbound[.moveTabUp]?.isEmpty == false)
    #expect(ShortcutConfiguration(preset: .safari).bindings[.moveTabUp]?.display == "⌥⌘↑")
    #expect(ShortcutPreset.arc.data.unbound[.previousProfile] == "The page lists no Profile command; Arc attaches a Profile to Spaces and switches it with them.")
    #expect(ShortcutPreset.zen.data.unbound[.nextProfile] == "The page lists no Profile command.")
    #expect(ShortcutPreset.safari.data.unbound[.nextProfile] == "The cited page lists no Profile shortcut.")
}

@Test(arguments: ShortcutPreset.allCases)
func showPreviousAndNextProfileFallBackToSafirasDefaultInEveryPreset(preset: ShortcutPreset) {
    let bindings = ShortcutConfiguration(preset: preset).bindings
    #expect(bindings[.previousProfile]?.display == "⌃⌥⌘←", "\(preset)")
    #expect(bindings[.nextProfile]?.display == "⌃⌥⌘→", "\(preset)")
}

@Test func theSpaceCommandsAMissingPresetEquivalentLeavesAreStillReachable() {
    func display(_ preset: ShortcutPreset, _ id: CommandID) -> String? {
        ShortcutConfiguration(preset: preset).bindings[id]?.display
    }
    #expect(display(.zen, .newSpace) == "⌃⌘N")
    #expect(display(.safari, .newSpace) == "⌃⌘N")
    #expect(display(.safari, .previousSpace) == "⌃⌘←")
    #expect(display(.safari, .nextSpace) == "⌃⌘→")
    #expect(display(.arc, .newSpace) == "⌃⌘N")
    #expect(display(.arc, .previousSpace) == "⌥⌘←")
    #expect(display(.arc, .nextSpace) == "⌥⌘→")
}

@Test func aFallbackNeverTakesAKeyThePresetAlreadyUses() throws {
    let json = #"{"preset":"zen","name":"Zen","source":"https://example.org","checked":"2026-11-04","bindings":{"reload":{"shortcut":"command+control+option+left","from":"x"}},"unbound":{"previousProfile":"no Profile command","nextProfile":"no Profile command"}}"#
    let bindings = ShortcutConfiguration.bindings(of: try PresetData.decode(Data(json.utf8)))
    #expect(bindings[.reload]?.display == "⌃⌥⌘←")
    #expect(bindings[.previousProfile] == nil)
    #expect(bindings[.nextProfile]?.display == "⌃⌥⌘→")
}

@Test func aMalformedPresetFileIsRejected() {
    func decode(_ json: String) throws -> PresetData { try PresetData.decode(Data(json.utf8)) }
    let valid = #"{"preset":"zen","name":"Zen","source":"https://example.org","checked":"2026-11-04","bindings":{"newTab":{"shortcut":"command+t","from":"x"}},"unbound":{}}"#
    #expect(throws: Never.self) { try decode(valid) }
    #expect(throws: (any Error).self) { try decode(valid.replacingOccurrences(of: "command+t", with: "command+wat")) }
    #expect(throws: (any Error).self) { try decode(valid.replacingOccurrences(of: "newTab", with: "newDoor")) }
    #expect(throws: (any Error).self) { try decode(valid.replacingOccurrences(of: "https://example.org", with: "http://example.org")) }
    #expect(throws: (any Error).self) { try decode(valid.replacingOccurrences(of: "\"zen\"", with: "\"vivaldi\"")) }
}

@Test func eachPresetOpensAPrivateWindowWithThePrivateWindowKeyOfItsSource() {
    func display(_ preset: ShortcutPreset) -> String? { ShortcutConfiguration(preset: preset).bindings[.newPrivateWindow]?.display }
    #expect(display(.safari) == "⇧⌘N")
    #expect(display(.arc) == "⇧⌘N")
    #expect(display(.zen) == "⇧⌘P")
    #expect(ShortcutPreset.zen.data.bindings[.newPrivateWindow]?.from == "Open Private Browsing Window (Shift+Ctrl+P)")
    #expect(ShortcutPreset.arc.data.bindings[.newPrivateWindow]?.from == "New incognito window (Command-Shift-N)")
}
