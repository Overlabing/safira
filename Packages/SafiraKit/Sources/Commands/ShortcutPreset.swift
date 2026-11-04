// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// A named set of keyboard shortcuts, chosen at onboarding and editable afterwards.
public enum ShortcutPreset: String, CaseIterable, Sendable, Codable {
    case zen
    case arc
    case safari

    /// The preset's data file, read once. A malformed file is a bug the preset tests catch, never a user's state.
    public var data: PresetData {
        do {
            return try PresetData.load(self)
        } catch {
            preconditionFailure("Presets/\(rawValue).json is unreadable: \(error)")
        }
    }
}

/// One preset as its JSON file states it: where the shortcuts come from, when they were checked, and for each command
/// either its shortcut or the reason it has none.
public struct PresetData: Sendable {
    public struct Binding: Sendable {
        public let shortcut: Shortcut
        /// Where the shortcut comes from: the action's name on the cited page, or why it is not on it.
        public let from: String
    }

    public let preset: ShortcutPreset
    public let name: String
    /// The official page the shortcuts were read from.
    public let source: URL
    /// ISO date (yyyy-MM-dd) the source was last read.
    public let checked: String
    public let note: String?
    public let bindings: [CommandID: Binding]
    /// Commands the browser has no equivalent for, each with the reason. Such a command takes Safira's default shortcut
    /// when the preset leaves that key free (see `ShortcutConfiguration.bindings`).
    public let unbound: [CommandID: String]

    public struct Malformed: Error, CustomStringConvertible {
        public let description: String
    }

    public static func load(_ preset: ShortcutPreset) throws -> PresetData {
        guard let url = Bundle.module.url(forResource: preset.rawValue, withExtension: "json", subdirectory: "Presets") else {
            throw Malformed(description: "file missing from the bundle")
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> PresetData {
        let file = try JSONDecoder().decode(File.self, from: data)
        guard let preset = ShortcutPreset(rawValue: file.preset) else {
            throw Malformed(description: "unknown preset \(file.preset)")
        }
        guard let source = URL(string: file.source), source.scheme == "https" else {
            throw Malformed(description: "source is not an https URL")
        }
        var bindings: [CommandID: Binding] = [:]
        for (key, entry) in file.bindings {
            guard let id = CommandID(rawValue: key) else { throw Malformed(description: "unknown command \(key)") }
            guard let shortcut = Shortcut(parsing: entry.shortcut) else {
                throw Malformed(description: "\(key): unreadable shortcut \(entry.shortcut)")
            }
            bindings[id] = Binding(shortcut: shortcut, from: entry.from)
        }
        var unbound: [CommandID: String] = [:]
        for (key, reason) in file.unbound {
            guard let id = CommandID(rawValue: key) else { throw Malformed(description: "unknown command \(key)") }
            unbound[id] = reason
        }
        return PresetData(preset: preset, name: file.name, source: source, checked: file.checked, note: file.note,
                          bindings: bindings, unbound: unbound)
    }

    private struct File: Decodable {
        struct Entry: Decodable {
            let shortcut: String
            let from: String
        }

        let preset: String
        let name: String
        let source: String
        let checked: String
        let note: String?
        let bindings: [String: Entry]
        let unbound: [String: String]
    }
}

extension ShortcutPreset {
    /// The entry for the Shortcut preset: the user picks Zen, Arc or Safari, and may keep Safira's own shortcuts.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "shortcuts.preset",
                title: "Shortcut preset",
                value: "Chosen by you",
                explanation: "Zen, Arc or Safari shortcuts. A command the preset has no equivalent for keeps Safira's own "
                    + "shortcut. Without a preset, Safira's own shortcuts apply. You can change any shortcut afterwards.",
                whereToChange: "Safira menu, Shortcuts…",
                control: .choice
            ),
        ]
    }
}
