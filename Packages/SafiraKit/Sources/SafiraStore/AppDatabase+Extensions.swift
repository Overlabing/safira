// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import GRDB
import SafiraCore

extension AppDatabase {
    /// The installed extensions, in the order they were installed.
    public func installedExtensions() throws -> [InstalledExtension] {
        try queue.read { db in
            var disabled: [String: Set<ProfileID>] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT extension_id, profile_id FROM extension_disabled_profile") {
                if let profile = ProfileID(uuidString: row["profile_id"]) {
                    disabled[row["extension_id"], default: []].insert(profile)
                }
            }
            return try Row.fetchAll(db, sql: "SELECT * FROM installed_extension ORDER BY installed_at, id")
                .compactMap { row -> InstalledExtension? in
                    let id: String = row["id"]
                    let source: ExtensionSource
                    switch row["source_kind"] as String {
                    case "folder":
                        guard let bookmark: Data = row["bookmark"] else { return nil }
                        source = .folder(bookmark: bookmark)
                    case "archive":
                        guard let file: String = row["archive_file"] else { return nil }
                        source = .archive(fileName: file)
                    default:
                        return nil
                    }
                    return InstalledExtension(id: id, source: source, displayName: row["display_name"],
                                              version: row["version"],
                                              grantedPermissions: Self.list(row["granted_permissions"]),
                                              grantedMatchPatterns: Self.list(row["granted_match_patterns"]),
                                              disabledProfiles: disabled[id] ?? [],
                                              installedAt: Date(timeIntervalSince1970: row["installed_at"]))
                }
        }
    }

    /// Adds an installed extension, or saves every field of one already listed under its identifier.
    public func save(_ installed: InstalledExtension) throws {
        try queue.write { db in
            let (kind, bookmark, file): (String, Data?, String?) = switch installed.source {
            case .folder(let bookmark): ("folder", bookmark, nil)
            case .archive(let file): ("archive", nil, file)
            }
            try db.execute(sql: """
                INSERT INTO installed_extension (id, source_kind, bookmark, archive_file, display_name, version,
                    granted_permissions, granted_match_patterns, installed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (id) DO UPDATE SET source_kind = excluded.source_kind, bookmark = excluded.bookmark,
                    archive_file = excluded.archive_file, display_name = excluded.display_name,
                    version = excluded.version, granted_permissions = excluded.granted_permissions,
                    granted_match_patterns = excluded.granted_match_patterns
                """, arguments: [installed.id, kind, bookmark, file, installed.displayName, installed.version,
                                 Self.text(installed.grantedPermissions), Self.text(installed.grantedMatchPatterns),
                                 installed.installedAt.timeIntervalSince1970])
            try db.execute(sql: "DELETE FROM extension_disabled_profile WHERE extension_id = ?", arguments: [installed.id])
            for profile in installed.disabledProfiles {
                try db.execute(sql: "INSERT INTO extension_disabled_profile (extension_id, profile_id) VALUES (?, ?)",
                               arguments: [installed.id, profile.rawValue.uuidString])
            }
        }
    }

    /// Forgets an installed extension and its per-Profile switches.
    public func deleteInstalledExtension(_ id: String) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM installed_extension WHERE id = ?", arguments: [id])
        }
    }

    private static func text(_ list: [String]) -> String {
        String(decoding: (try? JSONEncoder().encode(list)) ?? Data("[]".utf8), as: UTF8.self)
    }

    private static func list(_ text: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
    }
}
