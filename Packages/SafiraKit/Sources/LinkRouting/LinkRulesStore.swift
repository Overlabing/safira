// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// Why the rules file was not changed. Whatever the reason, the file on disk is exactly as it was.
public enum LinkRulesEditError: Error, Hashable, Sendable {
    /// The file on disk is not a valid rules file: it is never overwritten, the user fixes or removes it.
    case existingFileInvalid(LinkRulesError)
    /// A file offered for import is not a valid rules file.
    case importInvalid(LinkRulesError)
    case noSuchRule
    /// Someone edited the file between reading and writing; nothing was written.
    case changedOnDisk
    case notSaved

    public var explanation: String {
        switch self {
        case .existingFileInvalid(let error):
            "The Link rules file is not valid, so it was left as it is. " + error.explanation
        case .importInvalid(let error): "The file is not a valid Link rules file. " + error.explanation
        case .noSuchRule: "That rule no longer exists."
        case .changedOnDisk: "The Link rules file changed while it was being edited. Try again."
        case .notSaved: "The Link rules file could not be saved."
        }
    }
}

/// How an imported file joins the rules already there.
public enum LinkRulesImportMode: Hashable, Sendable {
    /// The imported rules go after the existing ones, which keep their order and win on a tie.
    case addToEnd
    /// The imported file takes the place of the existing one.
    case replace
}

/// Edits the rules file in place. It works on the file's own JSON, so everything it does not touch survives: keys it
/// does not know, fields of a rule it does not edit, the native app switches. A file that is not valid is never
/// written, and each write replaces the file in one step, so an interruption leaves the old file or the new one.
public struct LinkRulesStore: Sendable {
    public let url: URL
    private let afterReadingForEdit: @Sendable () -> Void

    /// `afterReadingForEdit` runs between an edit's read and its write, the moment the changed-bytes guard covers.
    public init(url: URL, afterReadingForEdit: @escaping @Sendable () -> Void = {}) {
        self.url = url
        self.afterReadingForEdit = afterReadingForEdit
    }

    /// The rules file is read through the same reader that routing uses.
    public func load() -> LinkRulesLoad {
        LinkRulesFile(url: url).load()
    }

    /// Adds a rule at the bottom. The Link picker only asks when no rule resolved the link, so a rule added last
    /// never changes where a link that an earlier rule already sends goes.
    public func append(_ rule: LinkRule) throws {
        try edit { $0.append(Self.object(for: rule)) }
    }

    public func remove(at index: Int) throws {
        try edit { rules in
            guard rules.indices.contains(index) else { throw LinkRulesEditError.noSuchRule }
            rules.remove(at: index)
        }
    }

    /// Moves the rule at `index` so it sits at `destination` once it is out of its old place.
    public func move(from index: Int, to destination: Int) throws {
        try edit { rules in
            guard rules.indices.contains(index), rules.indices.contains(destination) else {
                throw LinkRulesEditError.noSuchRule
            }
            rules.insert(rules.remove(at: index), at: destination)
        }
    }

    public func append(contentsOf rules: [LinkRule]) throws {
        try edit { $0.append(contentsOf: rules.map(Self.object(for:))) }
    }

    /// The rules file as it is, ready to save. A missing file exports an empty list of rules.
    public func exportData() throws -> Data {
        let (original, _) = try read()
        return original ?? Self.serialize(Self.emptyRoot)
    }

    /// Takes the rules of a file offered by the user. The file is checked before anything is written: an invalid one is
    /// refused and the existing rules stay.
    public func importFile(_ data: Data, mode: LinkRulesImportMode) throws {
        if case .failure(let error) = LinkRuleSet.parse(data) { throw LinkRulesEditError.importInvalid(error) }
        guard let imported = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LinkRulesEditError.importInvalid(.notJSON)
        }
        switch mode {
        case .replace:
            let (original, _) = try readForEdit()
            try write(Self.serialize(imported), replacing: original)
        case .addToEnd:
            let importedRules = imported["rules"] as? [Any] ?? []
            try edit { $0.append(contentsOf: importedRules) }
        }
    }

    // MARK: - Reading and writing

    private static var emptyRoot: [String: Any] { ["version": 1, "rules": [Any]()] }

    /// The bytes now on disk (nil when there is no file) and the file as JSON; throws when it is not valid.
    private func read() throws -> (original: Data?, root: [String: Any]) {
        let original: Data
        do {
            original = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return (nil, Self.emptyRoot)
        } catch {
            throw LinkRulesEditError.existingFileInvalid(.unreadable)
        }
        if case .failure(let error) = LinkRuleSet.parse(original) { throw LinkRulesEditError.existingFileInvalid(error) }
        guard let root = try? JSONSerialization.jsonObject(with: original) as? [String: Any] else {
            throw LinkRulesEditError.existingFileInvalid(.notJSON)
        }
        return (original, root)
    }

    private func readForEdit() throws -> (original: Data?, root: [String: Any]) {
        let result = try read()
        afterReadingForEdit()
        return result
    }

    private func edit(_ change: (inout [Any]) throws -> Void) throws {
        var (original, root) = try readForEdit()
        var rules = root["rules"] as? [Any] ?? []
        try change(&rules)
        root["rules"] = rules
        try write(Self.serialize(root), replacing: original)
    }

    /// Writes `data` over the file, but only if the file is still the bytes that were read.
    private func write(_ data: Data, replacing original: Data?) throws {
        let current = try? Data(contentsOf: url)
        guard current == original else { throw LinkRulesEditError.changedOnDisk }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw LinkRulesEditError.notSaved
        }
    }

    private static func serialize(_ root: [String: Any]) -> Data {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let json = (try? JSONSerialization.data(withJSONObject: root, options: options)) ?? Data()
        return json + Data("\n".utf8)
    }

    private static func object(for rule: LinkRule) -> [String: Any] {
        var fields: [String: Any] = ["profile": rule.profile]
        if let host = rule.host { fields["host"] = host }
        if let path = rule.path { fields["path"] = path }
        if let opener = rule.opener { fields["opener"] = opener }
        if let space = rule.space { fields["space"] = space }
        if rule.forcesNewTab { fields["newTab"] = true }
        return fields
    }
}
