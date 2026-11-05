// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
import Foundation
import Preferences
import SafiraCore

/// Keeps the user's shortcuts across launches under one key, in CommandKit's format: the set chosen (`safira` until a
/// preset is) and the commands the user changed, `{"base": "arc", "overrides": {"reload": ["⌥⌘J"], "moveTabUp": []}}`.
/// An override this version no longer reads (a command renamed since) is dropped, never fatal.
public struct ShortcutStore: Sendable {
    public static let key = "shortcuts.bindings"
    /// Until CommandKit, the preset's name and the overrides were two preferences, the shortcuts written
    /// "command+shift+t" and an empty text for a removed one. `load` moves them to `key` once.
    public static let presetKey = "shortcuts.preset"
    public static let overridesKey = "shortcuts.overrides"
    /// Before AppSupportKit, the same two keys held plain property-list values; `LegacyPreference.migrate` turns them
    /// into JSON at launch, before `load` reads them.
    public static let legacy = [
        LegacyPreference(key: presetKey, as: String?.self) { ($0 as? String).map { String?.some($0) } },
        LegacyPreference(key: overridesKey, as: [String: String].self) { $0 as? [String: String] },
    ]

    private let store: any KeyValueStore

    public init(store: any KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    /// - Parameter unreadable: told when the saved shortcuts could not be read and Safira's own replaced them.
    public func load(unreadable: (PreferenceError) -> Void) -> ShortcutBindings<CommandID> {
        let standard = ShortcutBindings(set: SafiraShortcuts.standard)
        guard let data = store.data(forKey: Self.key) ?? migratedOldKeys() else { return standard }
        do {
            let read = try ShortcutBindings.read(data, sets: SafiraShortcuts.sets, standard: standard).bindings
            return ShortcutBindings(set: read.set, overrides: read.overrides.filter { SafiraShortcuts.rules.isRebindable($0.key) })
        } catch {
            store.setData(nil, forKey: Self.key)
            unreadable(.unreadable(key: Self.key))
            return standard
        }
    }

    public func save(_ bindings: ShortcutBindings<CommandID>) {
        try? store.setData(bindings.data(), forKey: Self.key)
    }

    /// The bindings the two old keys described, written under `key`; the old keys are then removed, so this runs once.
    private func migratedOldKeys() -> Data? {
        let preset = Preference<String?>(key: Self.presetKey, defaultValue: nil, store: store)
        let overrides = Preference<[String: String]>(key: Self.overridesKey, defaultValue: [:], store: store)
        guard store.data(forKey: Self.presetKey) != nil || store.data(forKey: Self.overridesKey) != nil else { return nil }
        let set = SafiraShortcuts.set((try? preset.load())?.flatMap(ShortcutPreset.init(rawValue:)))
        var converted: [CommandID: [Shortcut]] = [:]
        for (name, text) in (try? overrides.load()) ?? [:] {
            guard let command = CommandID(rawValue: name) else { continue }
            if text.isEmpty {
                converted[command] = []
            } else if let shortcut = Self.shortcut(oldNotation: text) {
                converted[command] = [shortcut]
            }
        }
        let data = try? ShortcutBindings(set: set, overrides: converted).data()
        store.setData(data, forKey: Self.key)
        store.setData(nil, forKey: Self.presetKey)
        store.setData(nil, forKey: Self.overridesKey)
        return data
    }

    /// "control+option+command+left" as Safira wrote it before CommandKit; nil when a part is unknown or repeated.
    static func shortcut(oldNotation text: String) -> Shortcut? {
        let modifiers: [String: Shortcut.Modifier] = ["control": .control, "option": .option, "shift": .shift, "command": .command]
        let keys: [String: Character] = [
            "up": Shortcut.upArrow, "down": Shortcut.downArrow, "left": Shortcut.leftArrow, "right": Shortcut.rightArrow,
            "tab": Shortcut.tab, "return": Shortcut.returnKey, "escape": Shortcut.escape, "space": Shortcut.space,
            "delete": Shortcut.delete, "plus": "+",
        ]
        var held: Set<Shortcut.Modifier> = []
        var key: Character?
        for part in text.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init) {
            if let modifier = modifiers[part] {
                guard held.insert(modifier).inserted else { return nil }
            } else if key == nil, let named = keys[part] ?? (part.count == 1 ? part.first : nil) {
                key = named
            } else {
                return nil
            }
        }
        return key.map { Shortcut($0, held) }
    }
}
