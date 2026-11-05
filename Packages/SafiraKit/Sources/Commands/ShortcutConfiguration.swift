// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Preferences
import SafiraCore

/// What the user did to one command's shortcut.
public enum ShortcutOverride: Hashable, Sendable {
    case shortcut(Shortcut)
    /// The user removed the shortcut: the preset's one no longer applies.
    case unbound
}

/// The user's choice: a preset (none until they pick one) and the shortcuts they changed on top of it.
public struct ShortcutConfiguration: Hashable, Sendable {
    public var preset: ShortcutPreset?
    public var overrides: [CommandID: ShortcutOverride]

    public init(preset: ShortcutPreset? = nil, overrides: [CommandID: ShortcutOverride] = [:]) {
        self.preset = preset
        self.overrides = overrides
    }

    /// The bindings in force. Until a preset is chosen they are the registry defaults. With a preset, a command the
    /// preset binds takes its shortcut; a command it has no equivalent for (its `unbound` reason says why) falls back
    /// to Safira's default, unless the preset or an earlier fallback already uses that key, so Profile and Space
    /// switching never end up without a shortcut. A command that is not rebindable keeps its default whatever the
    /// preset says.
    public var bindings: KeyBindings {
        var bindings = preset.map { Self.bindings(of: $0.data) } ?? KeyBindings.defaults
        for (id, override) in overrides where CommandRegistry.command(id).isRebindable {
            switch override {
            case .shortcut(let shortcut): bindings[id] = shortcut
            case .unbound: bindings[id] = nil
            }
        }
        return bindings
    }

    public var conflicts: [ShortcutConflict] { bindings.conflicts }

    /// The bindings of one preset alone, fallbacks included.
    public static func bindings(of data: PresetData) -> KeyBindings {
        var bindings = KeyBindings.defaults
        let rebindable = CommandRegistry.commands.filter(\.isRebindable)
        for command in rebindable {
            bindings[command.id] = data.bindings[command.id]?.shortcut
        }
        var taken = Set(CommandRegistry.commands.compactMap { bindings[$0.id] })
        for command in rebindable where bindings[command.id] == nil && data.unbound[command.id] != nil {
            guard let fallback = command.defaultShortcut, taken.insert(fallback).inserted else { continue }
            bindings[command.id] = fallback
        }
        return bindings
    }
}

/// Keeps the configuration across launches, under two keys: the preset's name and the overrides as text. A saved value
/// that no longer parses (a command or shortcut renamed since) is dropped, never fatal.
public struct ShortcutStore: Sendable {
    public static let presetKey = "shortcuts.preset"
    public static let overridesKey = "shortcuts.overrides"
    /// Until AppSupportKit, the preset's name as plain text and the overrides as a dictionary of text.
    public static let legacy = [
        LegacyPreference(key: presetKey, as: String?.self) { ($0 as? String).map { String?.some($0) } },
        LegacyPreference(key: overridesKey, as: [String: String].self) { $0 as? [String: String] },
    ]
    private static let unboundMarker = ""
    private let preset: Preference<String?>
    private let overrides: Preference<[String: String]>

    public init(store: any KeyValueStore = UserDefaults.standard) {
        preset = Preference(key: Self.presetKey, defaultValue: nil, store: store)
        overrides = Preference(key: Self.overridesKey, defaultValue: [:], store: store)
    }

    public func load(unreadable: (PreferenceError) -> Void) -> ShortcutConfiguration {
        let preset = self.preset.loadRestoringDefault(unreadable).flatMap(ShortcutPreset.init(rawValue:))
        var overrides: [CommandID: ShortcutOverride] = [:]
        for (key, value) in self.overrides.loadRestoringDefault(unreadable) {
            guard let id = CommandID(rawValue: key) else { continue }
            if value == Self.unboundMarker {
                overrides[id] = .unbound
            } else if let shortcut = Shortcut(parsing: value) {
                overrides[id] = .shortcut(shortcut)
            }
        }
        return ShortcutConfiguration(preset: preset, overrides: overrides)
    }

    public func save(_ configuration: ShortcutConfiguration) {
        try? preset.save(configuration.preset?.rawValue)
        try? overrides.save(Dictionary(uniqueKeysWithValues: configuration.overrides.map { id, override in
            switch override {
            case .shortcut(let shortcut): (id.rawValue, shortcut.encoded)
            case .unbound: (id.rawValue, Self.unboundMarker)
            }
        }))
    }
}

/// The live shortcuts: the configuration the user edits, saved on every change, and the bindings and conflicts that
/// follow from it. Choosing another preset drops the overrides, since they were changes to the previous one.
@MainActor @Observable
public final class ShortcutController {
    public private(set) var configuration: ShortcutConfiguration
    public private(set) var bindings: KeyBindings
    public private(set) var conflicts: [ShortcutConflict]
    private let store: ShortcutStore

    /// - Parameter unreadable: told when a saved value could not be read and the defaults replaced it.
    public init(store: ShortcutStore = ShortcutStore(), unreadable: (PreferenceError) -> Void) {
        self.store = store
        let configuration = store.load(unreadable: unreadable)
        self.configuration = configuration
        bindings = configuration.bindings
        conflicts = configuration.conflicts
    }

    public func choose(_ preset: ShortcutPreset?) {
        update(ShortcutConfiguration(preset: preset))
    }

    public func setShortcut(_ shortcut: Shortcut?, for command: CommandID) {
        var configuration = configuration
        configuration.overrides[command] = shortcut.map(ShortcutOverride.shortcut) ?? .unbound
        update(configuration)
    }

    /// Back to what the preset (or the defaults) says for this command.
    public func resetShortcut(for command: CommandID) {
        var configuration = configuration
        configuration.overrides[command] = nil
        update(configuration)
    }

    public func resetAll() {
        update(ShortcutConfiguration(preset: configuration.preset))
    }

    private func update(_ configuration: ShortcutConfiguration) {
        self.configuration = configuration
        bindings = configuration.bindings
        conflicts = configuration.conflicts
        store.save(configuration)
    }
}
