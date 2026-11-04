// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// Why a ZenPicker rules file could not be read.
public enum ZenPickerImportError: Error, Hashable, Sendable {
    case notJSON
    /// The file is not a list of rules.
    case notAList
    /// The rule at `index` (from 0) is not an object of text fields.
    case invalidRule(index: Int)

    public var explanation: String {
        switch self {
        case .notJSON: "The file is not valid JSON."
        case .notAList: "The file is not a list of rules."
        case .invalidRule(let index): "Rule \(index + 1) is not an object of text fields."
        }
    }
}

/// A rules file of the ZenPicker script: a bare list of objects with `host`, `path`, `opener` and `target`, where the
/// target names a browser by a short key. Safira has Profiles instead, so each target is mapped to one by the user.
public struct ZenPickerRules: Hashable, Sendable {
    public struct Entry: Hashable, Sendable {
        public let host: String?
        public let path: String?
        public let opener: String?
        public let target: String?
    }

    public let entries: [Entry]

    /// The distinct targets, in the order they first appear.
    public var targets: [String] {
        var seen: Set<String> = []
        return entries.compactMap(\.target).filter { seen.insert($0).inserted }
    }

    public static func parse(_ data: Data) -> Result<ZenPickerRules, ZenPickerImportError> {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return .failure(.notJSON) }
        guard let list = root as? [Any] else { return .failure(.notAList) }
        var entries: [Entry] = []
        for (index, raw) in list.enumerated() {
            guard let fields = raw as? [String: Any] else { return .failure(.invalidRule(index: index)) }
            func text(_ key: String) -> String?? {
                guard let value = fields[key] else { return .some(nil) }
                guard let text = value as? String else { return nil }
                return .some(text)
            }
            guard let host = text("host"), let path = text("path"), let opener = text("opener"),
                  let target = text("target") else { return .failure(.invalidRule(index: index)) }
            entries.append(Entry(host: host, path: path, opener: opener, target: target))
        }
        return .success(ZenPickerRules(entries: entries))
    }

    /// The Link rules for the targets the user mapped. A rule whose target was not mapped, and a rule with neither a
    /// host nor an Opener (Safira ignores it), are left out and counted.
    ///
    /// - Parameter profileReference: for each target, the identifier of the Profile it becomes; a missing target is not
    ///   imported.
    public func linkRules(profileReference: [String: String]) -> (rules: [LinkRule], skipped: Int) {
        var rules: [LinkRule] = []
        for entry in entries {
            guard let target = entry.target, let profile = profileReference[target] else { continue }
            let rule = LinkRule(host: entry.host, path: entry.path, opener: entry.opener, profile: profile)
            if rule.isActive { rules.append(rule) }
        }
        return (rules, entries.count - rules.count)
    }
}
