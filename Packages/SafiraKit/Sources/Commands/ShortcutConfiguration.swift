// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

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

    /// The bindings in force. Until a preset is chosen they are the registry defaults; with a preset, a command it
    /// leaves unbound stays unbound. A command that is not rebindable keeps its default whatever the preset says.
    public var bindings: KeyBindings {
        var bindings = KeyBindings.defaults
        if let preset {
            let data = preset.data
            for command in CommandRegistry.commands where command.isRebindable {
                bindings[command.id] = data.bindings[command.id]?.shortcut
            }
        }
        for (id, override) in overrides where CommandRegistry.command(id).isRebindable {
            switch override {
            case .shortcut(let shortcut): bindings[id] = shortcut
            case .unbound: bindings[id] = nil
            }
        }
        return bindings
    }

    public var conflicts: [ShortcutConflict] { bindings.conflicts }
}

/// Keeps the configuration across launches in UserDefaults: three plain values, no schema to migrate. A saved value
/// that no longer parses (a command or shortcut renamed since) is dropped, never fatal.
public struct ShortcutStore: @unchecked Sendable {
    private static let presetKey = "shortcuts.preset"
    private static let overridesKey = "shortcuts.overrides"
    private static let unboundMarker = ""
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ShortcutConfiguration {
        let preset = defaults.string(forKey: Self.presetKey).flatMap(ShortcutPreset.init(rawValue:))
        var overrides: [CommandID: ShortcutOverride] = [:]
        for (key, value) in defaults.dictionary(forKey: Self.overridesKey) as? [String: String] ?? [:] {
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
        if let preset = configuration.preset {
            defaults.set(preset.rawValue, forKey: Self.presetKey)
        } else {
            defaults.removeObject(forKey: Self.presetKey)
        }
        let overrides = Dictionary(uniqueKeysWithValues: configuration.overrides.map { id, override in
            switch override {
            case .shortcut(let shortcut): (id.rawValue, shortcut.encoded)
            case .unbound: (id.rawValue, Self.unboundMarker)
            }
        })
        defaults.set(overrides, forKey: Self.overridesKey)
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

    public init(store: ShortcutStore = ShortcutStore()) {
        self.store = store
        let configuration = store.load()
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
