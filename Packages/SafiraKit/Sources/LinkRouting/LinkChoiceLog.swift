// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// Whether the Link picker keeps a log of the user's choices. Off until the user turns it on.
public struct LinkChoiceLogSettings: Hashable, Sendable, Codable {
    public var isEnabled: Bool

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public static let title = "Log Link picker choices"

    public static let explanation =
        "Writes the host of each link you send to a Profile, and the Profile, to a file on this Mac, never the path "
        + "or anything after it. The file stays on this Mac; Safira never sends it anywhere."

    /// The entry this type contributes to the registry of defaults, with the value of a fresh `LinkChoiceLogSettings`.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "linkPicker.choiceLog",
                title: title,
                value: LinkChoiceLogSettings().isEnabled ? "On" : "Off",
                explanation: explanation,
                whereToChange: "Safira menu",
                control: .toggle(isOn: LinkChoiceLogSettings().isEnabled)
            ),
        ]
    }
}

/// Keeps the choice log setting across launches.
public struct LinkChoiceLogSettingsStore: @unchecked Sendable {
    private static let key = "linkPicker.choiceLog"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> LinkChoiceLogSettings {
        LinkChoiceLogSettings(isEnabled: defaults.bool(forKey: Self.key))
    }

    public func save(_ settings: LinkChoiceLogSettings) {
        defaults.set(settings.isEnabled, forKey: Self.key)
    }
}

/// The local record of which Profile received which site through the Link picker: one JSON line per choice, holding
/// the host and the Profile and nothing else. A link with no host (a local file) is not recorded.
@MainActor
public final class LinkChoiceLog {
    public var isEnabled: Bool
    private let file: URL
    private let onError: @MainActor (any Error) -> Void

    private struct Entry: Encodable {
        let host: String
        let profile: String
    }

    public init(file: URL, isEnabled: Bool, onError: @escaping @MainActor (any Error) -> Void = { _ in }) {
        self.file = file
        self.isEnabled = isEnabled
        self.onError = onError
    }

    public func record(_ url: URL, chosen profile: ProfileID) {
        guard isEnabled, let host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            let line = try encoder.encode(Entry(host: host, profile: profile.rawValue.uuidString)) + Data("\n".utf8)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                try Data().write(to: file)
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } catch {
            onError(error)
        }
    }
}
