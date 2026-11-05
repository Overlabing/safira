// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
import Commands
import Foundation
import Testing

@Test func thePresetsAreZenArcAndSafari() {
    #expect(ShortcutPreset.allCases.map(\.rawValue) == ["zen", "arc", "safari"])
    #expect(ShortcutPreset.allCases.map(\.name) == ["Zen", "Arc", "Safari"])
    #expect(ShortcutPreset.allCases.map(\.set.id) == ["zen", "arc", "safari"])
    #expect(ShortcutPreset(SafiraShortcuts.standard) == nil)
    #expect(ShortcutPreset(ShortcutPreset.arc.set) == .arc)
}

@Test(arguments: ShortcutPreset.allCases)
func aPresetCitesAnHttpsSourceAndAnIsoCheckDate(preset: ShortcutPreset) throws {
    let set = preset.set
    #expect(set.source?.scheme == "https")
    #expect(try #require(set.checked).wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil)
}

@Test(arguments: ShortcutPreset.allCases)
func aPresetBindsOrExplainsEveryRebindableCommand(preset: ShortcutPreset) {
    let set = preset.set
    for command in rebindable {
        let bound = set.own[command] != nil
        let explained = !((set.notFound[command] ?? nil) ?? "").isEmpty
        #expect(bound != explained, "\(preset) must either bind or explain \(command), not both nor neither")
    }
    for command in Array(set.own.keys) + Array(set.notFound.keys) {
        #expect(SafiraShortcuts.rules.isRebindable(command))
    }
}

@Test(arguments: ShortcutPreset.allCases)
func aPresetSaysWhereEachShortcutComesFrom(preset: ShortcutPreset) {
    for (command, keys) in preset.set.own {
        #expect(keys.count == 1, "\(preset) \(command)")
        for key in keys {
            #expect(!(key.from ?? "").isEmpty, "\(preset) \(command)")
        }
    }
}

@Test(arguments: ShortcutPreset.allCases)
func aPresetHasNoConflictAndTakesNoFixedMenuKey(preset: ShortcutPreset) {
    #expect(bindings(preset).conflicts == [])
    for command in CommandID.allCases {
        for key in bindings(preset).keys(command) {
            #expect(!SafiraShortcuts.rules.reserved.contains(key), "\(preset) \(command) \(key.symbols)")
        }
    }
}

@Test(arguments: ShortcutPreset.allCases)
func aPresetSaysHowItsSourceWasRead(preset: ShortcutPreset) throws {
    let note = try #require(preset.set.note)
    #expect(!note.isEmpty)
    #expect(preset.localizedNote == note)
}

@Test func zenArcAndSafariKeepTheBrowserShortcutsInTheMenu() {
    for preset in ShortcutPreset.allCases {
        #expect(menuKey(preset, .newTab) == "⌘T", "\(preset)")
        #expect(menuKey(preset, .newWindow) == "⌘N", "\(preset)")
        #expect(menuKey(preset, .closeTab) == "⌘W", "\(preset)")
        #expect(menuKey(preset, .reopenClosedTab) == "⇧⌘T", "\(preset)")
        #expect(menuKey(preset, .openCommandBar) == "⌘L", "\(preset)")
        #expect(menuKey(preset, .quit) == "⌘Q", "\(preset)")
    }
}

@Test func thePresetsDifferWhereTheBrowsersDo() {
    #expect(key(.arc, .previousTab) == "⌥⌘↑")
    #expect(key(.arc, .nextTab) == "⌥⌘↓")
    #expect(key(.safari, .previousTab) == "⇧⌘[")
    #expect(key(.safari, .nextTab) == "⇧⌘]")
    #expect(key(.zen, .previousTab) == "⇧⌘[")
    #expect(key(.zen, .closeWindow) == "⇧⌘W")
}

@Test func aCommandTheBrowserDoesNotDocumentKeepsItsReasonAndInheritsSafirasKey() {
    #expect(ShortcutPreset.safari.set.inherits(.moveTabUp))
    #expect(bindings(.safari).isInherited(.moveTabUp))
    #expect(key(.safari, .moveTabUp) == "⌥⌘↑")
    #expect(ShortcutPreset.arc.set.notFound[.previousProfile]
        == .some("The page lists no Profile command; Arc attaches a Profile to Spaces and switches it with them."))
    #expect(ShortcutPreset.zen.set.notFound[.nextProfile] == .some("The page lists no Profile command."))
    #expect(ShortcutPreset.safari.set.notFound[.nextProfile] == .some("The cited page lists no Profile shortcut."))
    #expect(!bindings(.safari).isInherited(.newTab))
}

@Test(arguments: ShortcutPreset.allCases)
func showPreviousAndNextProfileInheritSafirasKeyInEveryPreset(preset: ShortcutPreset) {
    #expect(menuKey(preset, .previousProfile) == "⌃⌥⌘←", "\(preset)")
    #expect(menuKey(preset, .nextProfile) == "⌃⌥⌘→", "\(preset)")
}

@Test func theSpaceCommandsAPresetDoesNotDocumentAreStillReachable() {
    #expect(key(.zen, .newSpace) == "⌃⌘N")
    #expect(key(.safari, .newSpace) == "⌃⌘N")
    #expect(key(.safari, .previousSpace) == "⌃⌘←")
    #expect(key(.safari, .nextSpace) == "⌃⌘→")
    #expect(key(.arc, .newSpace) == "⌃⌘N")
    #expect(key(.arc, .previousSpace) == "⌥⌘←")
    #expect(key(.arc, .nextSpace) == "⌥⌘→")
}

private func preset(_ json: String) throws -> ShortcutSet<CommandID> {
    try ShortcutSet(data: Data(json.utf8), expecting: "zen", inheritingFrom: SafiraShortcuts.standard)
}

@Test func anInheritedKeyIsNeverOneThePresetAlreadyUses() throws {
    let set = try preset(#"{"id":"zen","shortcuts":{"reload":["⌃⌥⌘←"]},"notFound":{"previousProfile":"no Profile command","nextProfile":"no Profile command"}}"#)
    let bindings = ShortcutBindings(set: set)
    #expect(bindings.keys(.reload).map(\.symbols) == ["⌃⌥⌘←"])
    #expect(bindings.keys(.previousProfile) == [])
    #expect(bindings.keys(.nextProfile).map(\.symbols) == ["⌃⌥⌘→"])
}

/// CommandKit's rule, which differs from Safira's before it: a command a preset lists with no key gets none, where
/// Safira used to give it its own key; only a command the preset does not list, or lists under `notFound`, inherits.
@Test func aCommandListedWithNoKeyInheritsNothing() throws {
    let set = try preset(#"{"id":"zen","shortcuts":{"reload":[]},"notFound":["moveTabUp"]}"#)
    let bindings = ShortcutBindings(set: set)
    #expect(bindings.keys(.reload) == [])
    #expect(bindings.keys(.moveTabUp).map(\.symbols) == ["⌥⌘↑"])
    #expect(bindings.keys(.goBack).map(\.symbols) == ["⌘["])
    #expect(!bindings.isInherited(.goBack))
    #expect(bindings.isInherited(.moveTabUp))
}

@Test func aMalformedPresetFileIsRejected() {
    let valid = #"{"id":"zen","source":"https://example.org","checked":"2026-11-04","shortcuts":{"newTab":[{"shortcut":"⌘T","from":"x"}]},"notFound":{}}"#
    #expect(throws: Never.self) { try preset(valid) }
    #expect(throws: (any Error).self) { try preset(valid.replacingOccurrences(of: "⌘T", with: "command+t")) }
    #expect(throws: (any Error).self) { try preset(valid.replacingOccurrences(of: "newTab", with: "newDoor")) }
    #expect(throws: (any Error).self) { try preset(valid.replacingOccurrences(of: "\"zen\"", with: "\"vivaldi\"")) }
}

@Test func eachPresetOpensAPrivateWindowWithThePrivateWindowKeyOfItsSource() {
    #expect(key(.safari, .newPrivateWindow) == "⇧⌘N")
    #expect(key(.arc, .newPrivateWindow) == "⇧⌘N")
    #expect(key(.zen, .newPrivateWindow) == "⇧⌘P")
    #expect(ShortcutPreset.zen.set.own[.newPrivateWindow]?.first?.from == "Open Private Browsing Window (Shift+Ctrl+P)")
    #expect(ShortcutPreset.arc.set.own[.newPrivateWindow]?.first?.from == "New incognito window (Command-Shift-N)")
}
