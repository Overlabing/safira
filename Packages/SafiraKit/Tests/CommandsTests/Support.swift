// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
import Commands
import Foundation
import Preferences

/// The bindings of a preset with no change by the user, Safira's own without a preset.
func bindings(_ preset: ShortcutPreset?) -> ShortcutBindings<CommandID> {
    ShortcutBindings(set: SafiraShortcuts.set(preset))
}

/// A command's first key as the menu writes it, nil when it has none.
func key(_ preset: ShortcutPreset?, _ command: CommandID) -> String? {
    bindings(preset).keys(command).first?.symbols
}

/// The key of a command's menu item, nil when it has none.
func menuKey(_ preset: ShortcutPreset?, _ command: CommandID) -> String? {
    bindings(preset).shortcut(command)?.symbols
}

/// The commands with a behaviour behind them that a user can change.
let rebindable = CommandID.allCases.filter(SafiraShortcuts.rules.isRebindable)

/// A store holding `json` as the saved shortcuts.
func storeHolding(_ json: String) -> InMemoryKeyValueStore {
    let store = InMemoryKeyValueStore()
    store.setData(Data(json.utf8), forKey: ShortcutStore.key)
    return store
}
