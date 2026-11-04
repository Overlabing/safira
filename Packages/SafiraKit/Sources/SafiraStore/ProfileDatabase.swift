// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import GRDB
import SafiraCore

/// One Profile's database, `profile.sqlite` in the Profile's own folder. No API reads two Profiles at once.
public final class ProfileDatabase: Sendable {
    private let queue: DatabaseQueue

    public init(file: URL) throws {
        queue = try .opened(at: file, migrator: Migrations.profile)
    }

    /// A database that writes nothing to disk.
    public static func inMemory() throws -> ProfileDatabase {
        try ProfileDatabase(queue: DatabaseQueue())
    }

    private init(queue: DatabaseQueue) throws {
        self.queue = queue
        try Migrations.profile.migrate(queue)
    }

    public func savedSession() throws -> SavedSession {
        try queue.read { db in
            let space = try Self.spaceID(db)
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, url, title, interaction_state, state_os_build FROM tab WHERE space_id = ? ORDER BY position
                """, arguments: [space])
            let tabs = rows.compactMap { row -> TabRecord? in
                guard let id = UUID(uuidString: row["id"]) else { return nil }
                return TabRecord(
                    id: TabID(rawValue: id),
                    address: (row["url"] as String?).flatMap(URL.init(string:)),
                    title: row["title"],
                    navigationState: row["interaction_state"],
                    navigationStateOSBuild: row["state_os_build"]
                )
            }
            let selected = try String.fetchOne(db, sql: "SELECT selected_tab_id FROM space WHERE id = ?",
                                               arguments: [space])
                .flatMap(UUID.init(uuidString:))
                .map(TabID.init(rawValue:))
            return SavedSession(tabs: tabs, selectedTabID: tabs.contains { $0.id == selected } ? selected : nil)
        }
    }

    /// Replaces the saved Tabs in one transaction: a crash keeps either the previous session or this one.
    public func save(_ session: SavedSession) throws {
        try queue.write { db in try Self.write(session, db) }
    }

    public func save(_ session: SavedSession) async throws {
        try await queue.write { db in try Self.write(session, db) }
    }

    private static func write(_ session: SavedSession, _ db: Database) throws {
        let space = try spaceID(db)
        try db.execute(sql: "DELETE FROM tab WHERE space_id = ?", arguments: [space])
        for (position, tab) in session.tabs.enumerated() {
            try db.execute(sql: """
                INSERT INTO tab (id, space_id, position, url, title, interaction_state, state_os_build)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [tab.id.rawValue.uuidString, space, position, tab.address?.absoluteString, tab.title,
                                 tab.navigationState, tab.navigationStateOSBuild])
        }
        try db.execute(sql: "UPDATE space SET selected_tab_id = ? WHERE id = ?",
                       arguments: [session.selectedTabID?.rawValue.uuidString, space])
    }

    private static func spaceID(_ db: Database) throws -> String {
        guard let id = try String.fetchOne(db, sql: "SELECT id FROM space ORDER BY position LIMIT 1") else {
            throw DatabaseError(message: "the Profile database has no Space")
        }
        return id
    }
}
