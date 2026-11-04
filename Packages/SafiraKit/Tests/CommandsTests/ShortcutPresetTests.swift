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
    #expect(display(.zen, .previousTab) == nil)
    #expect(display(.arc, .closeWindow) == nil)
    #expect(display(.zen, .closeWindow) == "⇧⌘W")
}

@Test func aCommandWithNoEquivalentStaysUnboundAndSaysWhy() {
    #expect(ShortcutPreset.safari.data.unbound[.moveTabUp]?.isEmpty == false)
    #expect(ShortcutConfiguration(preset: .safari).bindings[.moveTabUp] == nil)
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
