// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Foundation
import Testing

/// A defaults domain of its own, removed afterwards: never Safira's real one.
private func scratchDefaults() -> (UserDefaults, cleanup: @Sendable () -> Void) {
    let name = "com.overlabing.safira.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    return (defaults, { UserDefaults.standard.removePersistentDomain(forName: name) })
}

@Test func nothingIsChosenAtFirstAndTheDefaultsApply() {
    let (defaults, cleanup) = scratchDefaults()
    defer { cleanup() }
    let configuration = ShortcutStore(defaults: defaults).load()
    #expect(configuration == ShortcutConfiguration())
    #expect(configuration.bindings == KeyBindings.defaults)
}

@Test func theChosenPresetAndTheOverridesSurviveARelaunch() {
    let (defaults, cleanup) = scratchDefaults()
    defer { cleanup() }
    var configuration = ShortcutConfiguration(preset: .arc)
    configuration.overrides[.reload] = .shortcut(Shortcut(.character("j"), [.command, .option]))
    configuration.overrides[.moveTabUp] = .unbound
    ShortcutStore(defaults: defaults).save(configuration)

    let reloaded = ShortcutStore(defaults: defaults).load()
    #expect(reloaded == configuration)
    #expect(reloaded.bindings[.reload]?.display == "⌥⌘J")
    #expect(reloaded.bindings[.previousTab]?.display == "⌥⌘↑")
}

@Test func aSavedValueThatNoLongerParsesIsDropped() {
    let (defaults, cleanup) = scratchDefaults()
    defer { cleanup() }
    defaults.set("vivaldi", forKey: "shortcuts.preset")
    defaults.set(["reload": "command+j", "gone": "command+g", "newTab": "command+wat"], forKey: "shortcuts.overrides")
    let configuration = ShortcutStore(defaults: defaults).load()
    #expect(configuration.preset == nil)
    #expect(configuration.overrides == [.reload: .shortcut(Shortcut(.character("j"), .command))])
}

@MainActor
@Test func theControllerSavesEveryChangeAndReportsConflicts() {
    let (defaults, cleanup) = scratchDefaults()
    defer { cleanup() }
    let controller = ShortcutController(store: ShortcutStore(defaults: defaults))
    controller.choose(.safari)
    controller.setShortcut(Shortcut(.character("l"), .command), for: .reload)
    #expect(controller.conflicts.map(\.commands) == [[.openCommandBar, .reload]])
    #expect(ShortcutController(store: ShortcutStore(defaults: defaults)).conflicts.map(\.commands) == [[.openCommandBar, .reload]])

    controller.setShortcut(nil, for: .reload)
    #expect(controller.conflicts == [])
    #expect(controller.bindings[.reload] == nil)
    controller.resetShortcut(for: .reload)
    #expect(controller.bindings[.reload]?.display == "⌘R")
}

@MainActor
@Test func choosingAnotherPresetDropsTheOverridesButResettingKeepsThePreset() {
    let (defaults, cleanup) = scratchDefaults()
    defer { cleanup() }
    let controller = ShortcutController(store: ShortcutStore(defaults: defaults))
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
