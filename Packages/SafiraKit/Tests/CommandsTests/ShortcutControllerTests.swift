// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
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

private func stored(_ store: any KeyValueStore) -> String? {
    store.data(forKey: ShortcutStore.key).flatMap { String(data: $0, encoding: .utf8) }
}

@MainActor
@Test func nothingIsChosenAtFirstAndSafirasOwnShortcutsApply() {
    let loaded = ShortcutStore(store: InMemoryKeyValueStore()).load(unreadable: ignored)
    #expect(loaded == ShortcutBindings(set: SafiraShortcuts.standard))
}

@MainActor
@Test func theChosenPresetAndTheChangesSurviveARelaunchInCommandKitsFormat() throws {
    let store = InMemoryKeyValueStore()
    let controller = ShortcutController(store: ShortcutStore(store: store), unreadable: ignored)
    controller.choose(.arc)
    #expect(controller.record(Shortcut("j", [.command, .option]), for: .reload) == nil)
    controller.unbind(.moveTabUp)
    #expect(stored(store) == #"{"base":"arc","overrides":{"moveTabUp":[],"reload":["⌥⌘J"]}}"#)

    let reloaded = ShortcutController(store: ShortcutStore(store: store), unreadable: ignored)
    #expect(reloaded.bindings == controller.bindings)
    #expect(reloaded.preset == .arc)
    #expect(reloaded.bindings.keys(.reload).map(\.symbols) == ["⌥⌘J"])
    #expect(reloaded.bindings.keys(.previousTab).map(\.symbols) == ["⌥⌘↑"])
}

/// "Unbound by the user": no key, overridden and not inherited, until the command is reset.
@MainActor
@Test func aCommandTheUserUnboundHasNoKeyUntilItIsReset() {
    let controller = ShortcutController(store: ShortcutStore(store: InMemoryKeyValueStore()), unreadable: ignored)
    controller.choose(.safari)
    controller.unbind(.moveTabUp)
    #expect(controller.bindings.keys(.moveTabUp) == [])
    #expect(controller.bindings.shortcut(.moveTabUp) == nil)
    #expect(controller.bindings.isOverridden(.moveTabUp))
    #expect(!controller.bindings.isInherited(.moveTabUp))
    controller.reset(.moveTabUp)
    #expect(controller.bindings.keys(.moveTabUp).map(\.symbols) == ["⌥⌘↑"])
    #expect(controller.bindings.isInherited(.moveTabUp))
    #expect(!controller.bindings.isOverridden(.moveTabUp))
}

@MainActor
@Test func aFixedCommandCannotBeUnbound() {
    let controller = ShortcutController(store: ShortcutStore(store: InMemoryKeyValueStore()), unreadable: ignored)
    controller.unbind(.commandBarNext)
    #expect(controller.bindings.keys(.commandBarNext).map(\.symbols) == ["⇥"])
    #expect(controller.bindings.overrides.isEmpty)
}

@MainActor
@Test func anOverrideThatNoLongerReadsIsDroppedAndTheOthersKept() {
    let store = storeHolding(#"{"base":"zen","overrides":{"reload":["⌘J"],"gone":["⌘G"],"newTab":["command+wat"],"commandBarNext":[]}}"#)
    var problems: [PreferenceError] = []
    let loaded = ShortcutStore(store: store).load { problems.append($0) }
    #expect(loaded == ShortcutBindings(set: SafiraShortcuts.set(.zen), overrides: [.reload: [Shortcut("j")]]))
    #expect(problems == [])
}

@MainActor
@Test func unreadableSavedShortcutsGiveSafirasOwnAndAreReported() {
    let store = storeHolding(#"{"base":"vivaldi","overrides":{}}"#)
    var problems: [PreferenceError] = []
    let loaded = ShortcutStore(store: store).load { problems.append($0) }
    #expect(loaded == ShortcutBindings(set: SafiraShortcuts.standard))
    #expect(problems == [.unreadable(key: "shortcuts.bindings")])
    #expect(store.data(forKey: ShortcutStore.key) == nil)
}

/// The two keys Safira wrote with AppSupportKit (#74) become CommandKit's one, once.
@MainActor
@Test func theShortcutsTheAppSupportKitStoreKeptAreMovedOnce() {
    let store = InMemoryKeyValueStore()
    store.setData(Data(#""arc""#.utf8), forKey: "shortcuts.preset")
    store.setData(Data(#"{"moveTabUp":"","reload":"command+option+j","newTab":"command+wat","gone":"command+g","goBack":"control+shift+command+left"}"#.utf8),
                  forKey: "shortcuts.overrides")

    let loaded = ShortcutStore(store: store).load(unreadable: ignored)

    #expect(loaded == ShortcutBindings(set: SafiraShortcuts.set(.arc), overrides: [
        .moveTabUp: [], .reload: [Shortcut("j", [.command, .option])],
        .goBack: [Shortcut(Shortcut.leftArrow, [.control, .shift, .command])],
    ]))
    #expect(stored(store) == #"{"base":"arc","overrides":{"goBack":["⌃⇧⌘←"],"moveTabUp":[],"reload":["⌥⌘J"]}}"#)
    #expect(store.data(forKey: "shortcuts.preset") == nil)
    #expect(store.data(forKey: "shortcuts.overrides") == nil)
    #expect(ShortcutStore(store: store).load(unreadable: ignored) == loaded)
}

@MainActor
@Test func overridesWithNoPresetMoveToSafirasOwnSet() {
    let store = InMemoryKeyValueStore()
    store.setData(Data(#"{"reload":"command+shift+plus"}"#.utf8), forKey: "shortcuts.overrides")
    #expect(stored(store) == nil)
    let loaded = ShortcutStore(store: store).load(unreadable: ignored)
    #expect(loaded.set.id == "safira")
    #expect(loaded.keys(.reload).map(\.symbols) == ["⇧⌘+"])
}

/// Before AppSupportKit the keys held plain property-list values: `LegacyPreference.migrate` (#74) runs first at
/// launch, then the store moves them to CommandKit's format.
@MainActor
@Test func theShortcutsTheFirstStoreKeptAreReadAfterBothMigrations() {
    let (defaults, domain, cleanup) = scratchDefaults()
    defer { cleanup() }
    defaults.set("arc", forKey: "shortcuts.preset")
    defaults.set(["reload": "command+option+j", "moveTabUp": ""], forKey: "shortcuts.overrides")

    LegacyPreference.migrate(ShortcutStore.legacy, in: defaults, domain: domain)
    let loaded = ShortcutStore(store: defaults).load(unreadable: ignored)

    #expect(loaded == ShortcutBindings(set: SafiraShortcuts.set(.arc),
                                       overrides: [.reload: [Shortcut("j", [.command, .option])], .moveTabUp: []]))
    #expect(defaults.object(forKey: "shortcuts.preset") == nil)
    #expect(defaults.object(forKey: "shortcuts.overrides") == nil)
}

@MainActor
@Test func theControllerSavesEveryChangeAndRefusesATakenKey() {
    let store = InMemoryKeyValueStore()
    let controller = ShortcutController(store: ShortcutStore(store: store), unreadable: ignored)
    controller.choose(.safari)
    #expect(controller.record(Shortcut("l"), for: .reload) == .taken(Shortcut("l"), by: .openCommandBar))
    #expect(controller.bindings.overrides.isEmpty)
    #expect(controller.record(Shortcut("j"), for: .reload) == nil)
    #expect(ShortcutController(store: ShortcutStore(store: store), unreadable: ignored).bindings.keys(.reload)
        == [Shortcut("j")])
    controller.reset(.reload)
    #expect(controller.bindings.keys(.reload).map(\.symbols) == ["⌘R"])
    #expect(controller.conflicts == [])
}

@MainActor
@Test func choosingAnotherPresetDropsTheChangesButResettingKeepsThePreset() {
    let controller = ShortcutController(store: ShortcutStore(store: InMemoryKeyValueStore()), unreadable: ignored)
    controller.choose(.zen)
    controller.record(Shortcut("j"), for: .reload)
    controller.resetAll()
    #expect(controller.bindings == ShortcutBindings(set: SafiraShortcuts.set(.zen)))
    controller.record(Shortcut("j"), for: .reload)
    controller.choose(.arc)
    #expect(controller.bindings == ShortcutBindings(set: SafiraShortcuts.set(.arc)))
    controller.choose(nil)
    #expect(controller.preset == nil)
    #expect(controller.bindings == ShortcutBindings(set: SafiraShortcuts.standard))
}

@MainActor
@Test func takingTheKeyBeforeTheFocusedViewFollowsTheController() {
    let controller = ShortcutController(store: ShortcutStore(store: InMemoryKeyValueStore()), unreadable: ignored)
    #expect(controller.takesKeyBeforeFocusedView(Shortcut("w")))
    controller.unbind(.closeTab)
    #expect(!controller.takesKeyBeforeFocusedView(Shortcut("w")))
}
