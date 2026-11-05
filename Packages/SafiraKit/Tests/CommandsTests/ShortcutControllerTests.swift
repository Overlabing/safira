// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Foundation
import Preferences
import SafiraCore
import Testing

/// A defaults domain of its own, removed afterwards: never Safira's real one.
private func scratchDefaults() -> (UserDefaults, domain: String, cleanup: @Sendable () -> Void) {
    let name = "com.overlabing.safira.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (defaults, name, { UserDefaults.standard.removePersistentDomain(forName: name) })
}

private func ignored(_ problem: PreferenceError) {}

@Test func nothingIsChosenAtFirstAndTheDefaultsApply() {
    let configuration = ShortcutStore(store: InMemoryKeyValueStore()).load(unreadable: ignored)
    #expect(configuration == ShortcutConfiguration())
    #expect(configuration.bindings == KeyBindings.defaults)
}

@Test func theChosenPresetAndTheOverridesSurviveARelaunch() {
    let store = InMemoryKeyValueStore()
    var configuration = ShortcutConfiguration(preset: .arc)
    configuration.overrides[.reload] = .shortcut(Shortcut(.character("j"), [.command, .option]))
    configuration.overrides[.moveTabUp] = .unbound
    ShortcutStore(store: store).save(configuration)

    let reloaded = ShortcutStore(store: store).load(unreadable: ignored)
    #expect(reloaded == configuration)
    #expect(reloaded.bindings[.reload]?.display == "⌥⌘J")
    #expect(reloaded.bindings[.previousTab]?.display == "⌥⌘↑")
}

@Test func aSavedValueThatNoLongerParsesIsDropped() {
    let store = InMemoryKeyValueStore()
    store.setData(Data(#""vivaldi""#.utf8), forKey: "shortcuts.preset")
    store.setData(Data(#"{"reload": "command+j", "gone": "command+g", "newTab": "command+wat"}"#.utf8),
                  forKey: "shortcuts.overrides")
    var problems: [PreferenceError] = []
    let configuration = ShortcutStore(store: store).load { problems.append($0) }
    #expect(configuration.preset == nil)
    #expect(configuration.overrides == [.reload: .shortcut(Shortcut(.character("j"), .command))])
    #expect(problems == [])
}

@Test func theShortcutsTheOldStoreKeptAreReadAfterTheMigration() {
    let (defaults, domain, cleanup) = scratchDefaults()
    defer { cleanup() }
    defaults.set("arc", forKey: "shortcuts.preset")
    defaults.set(["reload": "command+option+j", "moveTabUp": ""], forKey: "shortcuts.overrides")

    LegacyPreference.migrate(ShortcutStore.legacy, in: defaults, domain: domain)

    var expected = ShortcutConfiguration(preset: .arc)
    expected.overrides[.reload] = .shortcut(Shortcut(.character("j"), [.command, .option]))
    expected.overrides[.moveTabUp] = .unbound
    #expect(ShortcutStore(store: defaults).load(unreadable: ignored) == expected)
}

@MainActor
@Test func theControllerSavesEveryChangeAndReportsConflicts() {
    let store = InMemoryKeyValueStore()
    let controller = ShortcutController(store: ShortcutStore(store: store), unreadable: ignored)
    controller.choose(.safari)
    controller.setShortcut(Shortcut(.character("l"), .command), for: .reload)
    #expect(controller.conflicts.map(\.commands) == [[.openCommandBar, .reload]])
    #expect(ShortcutController(store: ShortcutStore(store: store), unreadable: ignored).conflicts.map(\.commands) == [[.openCommandBar, .reload]])

    controller.setShortcut(nil, for: .reload)
    #expect(controller.conflicts == [])
    #expect(controller.bindings[.reload] == nil)
    controller.resetShortcut(for: .reload)
    #expect(controller.bindings[.reload]?.display == "⌘R")
}

@MainActor
@Test func choosingAnotherPresetDropsTheOverridesButResettingKeepsThePreset() {
    let controller = ShortcutController(store: ShortcutStore(store: InMemoryKeyValueStore()), unreadable: ignored)
    controller.choose(.zen)
    controller.setShortcut(Shortcut(.character("j"), .command), for: .reload)
    controller.resetAll()
    #expect(controller.configuration == ShortcutConfiguration(preset: .zen))
    controller.setShortcut(Shortcut(.character("j"), .command), for: .reload)
    controller.choose(.arc)
    #expect(controller.configuration == ShortcutConfiguration(preset: .arc))
    controller.choose(nil)
    #expect(controller.bindings == KeyBindings.defaults)
}
