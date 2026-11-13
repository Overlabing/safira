// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
import Commands
import Testing

@Test func everyCommandHasItsOwnTitle() {
    #expect(Set(CommandID.allCases.map(\.title)).count == CommandID.allCases.count)
    #expect(CommandID.allCases.count == 55)
    #expect(CommandID.compactMode.title == "Compact Mode")
    #expect(CommandID.showSidebar.title == "Show Sidebar")
    #expect(CommandID.selectTab1.title == "Show Tab 1")
    #expect(CommandID.selectSpace9.title == "Show Space 9")
}

/// The menu item names what it will do to the selected Tab; the Shortcuts row reads as the menu does for a plain Tab.
@Test func thePinCommandHasAStateLabelNotACombinedOne() {
    #expect(CommandID.togglePin.title == "Pin Tab")
    #expect(!CommandID.allCases.contains { $0.title.contains("Pin or Unpin") })
}

@Test func theDefaultsAreTheProductDefaultsDecidedSoFar() {
    #expect(key(nil, .newTab) == "⌘T")
    #expect(key(nil, .newWindow) == "⌘N")
    #expect(key(nil, .closeTab) == "⌘W")
    #expect(key(nil, .reopenClosedTab) == "⇧⌘T")
    #expect(key(nil, .openCommandBar) == "⌘L")
    #expect(key(nil, .quit) == "⌘Q")
    #expect(key(nil, .compactMode) == "⌃⌘S")
    #expect(key(nil, .showSidebar) == "⌥⌘S")
    #expect(key(nil, .previousTab) == "⇧⌘[")
    #expect(key(nil, .nextTab) == "⇧⌘]")
    #expect(key(nil, .moveTabUp) == "⌥⌘↑")
    #expect(key(nil, .moveTabDown) == "⌥⌘↓")
    #expect(key(nil, .commandBarNext) == "⇥")
    #expect(key(nil, .commandBarPrevious) == "⇧⇥")
    #expect(key(nil, .newPrivateWindow) == "⇧⌘N")
    #expect(key(nil, .showDownloads) == "⌥⌘L")
    #expect(bindings(nil).conflicts == [])
}

@Test func safirasOwnSetHasNoParentAndNamesNoSource() {
    let standard = SafiraShortcuts.standard
    #expect(standard.id == "safira")
    #expect(standard.source == nil)
    #expect(standard.notFound.isEmpty)
    #expect(SafiraShortcuts.sets.map(\.id) == ["safira", "zen", "arc", "safari"])
}

@Test func theCommandBarKeysAreFixed() {
    for command in [CommandID.commandBarNext, .commandBarPrevious] {
        #expect(!SafiraShortcuts.rules.isRebindable(command))
    }
    #expect(rebindable.count == 53)
}

@Test func aFixedCommandRefusesARecordedKey() {
    var arc = bindings(.arc)
    #expect(throws: ShortcutBindingError<CommandID>.notRebindable(.commandBarNext)) {
        try arc.record(Shortcut("j"), for: .commandBarNext, rules: SafiraShortcuts.rules)
    }
    #expect(arc.keys(.commandBarNext).map(\.symbols) == ["⇥"])
}

@Test func theSpaceCommandsUseControlCommandKeys() {
    #expect(key(nil, .newSpace) == "⌃⌘N")
    #expect(key(nil, .previousSpace) == "⌃⌘←")
    #expect(key(nil, .nextSpace) == "⌃⌘→")
    for command in [CommandID.renameSpace, .deleteSpace, .moveSpaceLeft, .moveSpaceRight] {
        #expect(key(nil, command) == nil)
        #expect(SafiraShortcuts.rules.isRebindable(command))
    }
}

/// CommandKit 0.1.3's rule (`Shortcut.editsText`): only ⌘ or ⇧⌘ with an arrow, and ⌫ alone, with one of ⇧ ⌥ ⌃ or with ⌘
/// alone, edit the text of a field. ⌃⌘←, ⌃⌘→ (Show Previous and Next Space) and ⇧⌘⌫ (Clear History) are menu keys, so
/// every key of every set reaches its menu item.
@Test func everyKeyOfEverySetIsAMenuKey() {
    #expect(menuKey(nil, .previousSpace) == "⌃⌘←")
    #expect(menuKey(nil, .nextSpace) == "⌃⌘→")
    #expect(menuKey(nil, .clearBrowsingData) == "⇧⌘⌫")
    #expect(menuKey(.safari, .previousSpace) == "⌃⌘←")
    #expect(menuKey(.safari, .nextSpace) == "⌃⌘→")
    for preset in ShortcutPreset.allCases {
        #expect(menuKey(preset, .clearBrowsingData) == "⇧⌘⌫", "\(preset)")
    }
    #expect(menuKey(.arc, .previousSpace) == "⌥⌘←")
    #expect(menuKey(nil, .previousProfile) == "⌃⌥⌘←")
    var withoutMenuKey: [String] = []
    for preset in [nil] + ShortcutPreset.allCases.map(Optional.some) {
        withoutMenuKey += CommandID.allCases.filter { !bindings(preset).keys($0).isEmpty && menuKey(preset, $0) == nil }
            .map { "\(preset?.rawValue ?? "safira") \($0)" }
    }
    #expect(withoutMenuKey == [])
}

@Test func arcAndZenSwitchSpacesWithTheirOwnKeys() {
    #expect(key(.arc, .previousSpace) == "⌥⌘←")
    #expect(key(.arc, .nextSpace) == "⌥⌘→")
    #expect(key(.zen, .previousSpace) == "⌥⌘Q")
    #expect(key(.zen, .nextSpace) == "⌥⌘E")
    #expect(key(.safari, .nextSpace) == "⌃⌘→")
}

@Test func zenBindsClearBrowsingDataFromItsPageAndArcAndSafariInheritSafirasKey() {
    #expect(ShortcutPreset.zen.set.own[.clearBrowsingData]?.first?.from == "Clear Browsing Data (Shift+Ctrl+Delete)")
    #expect(key(nil, .clearBrowsingData) == "⇧⌘⌫")
    #expect(key(.zen, .clearBrowsingData) == "⇧⌘⌫")
    #expect(ShortcutPreset.arc.set.inherits(.clearBrowsingData))
    #expect(ShortcutPreset.safari.set.inherits(.clearBrowsingData))
    #expect(key(.arc, .clearBrowsingData) == "⇧⌘⌫")
    #expect(key(.safari, .clearBrowsingData) == "⇧⌘⌫")
}

@Test func thePinCommandsHaveNoDefaultShortcutAndOnlyArcPinsATab() {
    #expect(key(nil, .togglePin) == nil)
    #expect(key(nil, .newFolder) == nil)
    #expect(key(.arc, .togglePin) == "⌘D")
    #expect(key(.zen, .togglePin) == nil)
    #expect(key(.safari, .togglePin) == nil)
    for preset in ShortcutPreset.allCases {
        #expect(key(preset, .newFolder) == nil)
    }
}

@Test func theDownloadsCommandInheritsSafirasKeyWhereAPresetHasNone() {
    #expect(CommandID.showDownloads.title == "Downloads")
    #expect(key(.zen, .showDownloads) == "⇧⌘Y")
    #expect(key(.arc, .showDownloads) == "⌥⌘L")
    #expect(key(.safari, .showDownloads) == "⌥⌘L")
}

@Test func commandOneToNineShowATabAndControlOneToNineShowASpace() {
    #expect(CommandID.selectTabCommands.map { key(nil, $0) } == ["⌘1", "⌘2", "⌘3", "⌘4", "⌘5", "⌘6", "⌘7", "⌘8", "⌘9"])
    #expect(CommandID.selectSpaceCommands.map { key(nil, $0) } == ["⌃1", "⌃2", "⌃3", "⌃4", "⌃5", "⌃6", "⌃7", "⌃8", "⌃9"])
    #expect(CommandID.selectTab4.tabNumber == 4)
    #expect(CommandID.selectTab4.spaceNumber == nil)
    #expect(CommandID.selectSpace7.spaceNumber == 7)
    #expect(CommandID.newTab.tabNumber == nil)
}

@Test func everyPresetKeepsTheNumberedKeysAndSafariAndZenCiteTheirTabKeys() {
    for preset in ShortcutPreset.allCases {
        #expect(key(preset, .selectTab1) == "⌘1")
        #expect(key(preset, .selectTab9) == "⌘9")
        #expect(key(preset, .selectSpace1) == "⌃1")
        #expect(key(preset, .selectSpace9) == "⌃9")
    }
    #expect(ShortcutPreset.safari.set.own[.selectTab8]?.first?.from == "Select one of your first eight tabs (Command-1 to Command-8)")
    #expect(ShortcutPreset.safari.set.notFound[.selectTab9] == .some("Safari's Command-9 selects the last tab, not the ninth; Safira's own key applies."))
    #expect(ShortcutPreset.zen.set.own[.selectTab1]?.first?.shortcut.symbols == "⌘1")
    #expect(ShortcutPreset.zen.set.notFound[.selectSpace1] == .some("Switch to Workspace (1-10) is not set by default."))
    #expect(ShortcutPreset.arc.set.own[.selectTab1] == nil)
}

@Test func theShortcutsWindowShowsEveryImplementedCommandOnce() {
    let listed = SafiraShortcuts.groups.flatMap(\.commands)
    #expect(listed.count == Set(listed).count)
    #expect(Set(listed) == Set(CommandID.allCases.filter(\.isImplemented)))
    #expect(!CommandID.newWindow.isImplemented)
    #expect(SafiraShortcuts.groups.map(\.title) == ["Tabs and Windows", "View and History", "Spaces", "Profiles", "Command Bar"])
}
