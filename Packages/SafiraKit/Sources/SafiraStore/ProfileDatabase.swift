// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import GRDB
import SafiraCore

/// One Profile's database, `profile.sqlite` in the Profile's own folder. No API reads two Profiles at once.
public final class ProfileDatabase: Sendable {
    let queue: DatabaseQueue

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

    /// Every Space with its Tabs, in sidebar order, and the active Space.
    public func savedSession() throws -> SavedSession {
        try queue.read { db in
            let spaces = try Row.fetchAll(db, sql: """
                SELECT id, name, emoji, palette_id, selected_tab_id FROM space ORDER BY position
                """).compactMap { row -> SpaceRecord? in
                guard let id = SpaceID(uuidString: row["id"]) else { return nil }
                let tabs = try Self.tabs(of: row["id"], db)
                let selected = (row["selected_tab_id"] as String?).flatMap(UUID.init(uuidString:)).map(TabID.init(rawValue:))
                return SpaceRecord(id: id, name: row["name"], emoji: row["emoji"], paletteID: row["palette_id"],
                                   tabs: tabs, selectedTabID: tabs.contains { $0.id == selected } ? selected : nil)
            }
            let active = try String.fetchOne(db, sql: "SELECT value FROM profile_setting WHERE key = ?",
                                             arguments: [Self.activeSpaceKey])
                .flatMap(SpaceID.init(uuidString:))
            return SavedSession(spaces: spaces, activeSpaceID: spaces.contains { $0.id == active } ? active : nil)
        }
    }

    /// Replaces the saved Spaces and Tabs in one transaction: a crash keeps either the previous session or this one.
    public func save(_ session: SavedSession) throws {
        try queue.write { db in try Self.write(session, db) }
    }

    public func save(_ session: SavedSession) async throws {
        try await queue.write { db in try Self.write(session, db) }
    }

    /// The Profile's own settings. A setting never saved reads as its default; an engine this build does not know reads
    /// as none, so the user is asked again.
    public func settings() throws -> ProfileSettings {
        try queue.read { db in
            let values = try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: "SELECT key, value FROM profile_setting")
                .map { ($0["key"] as String, $0["value"] as String) })
            let defaults = WebContentSettings()
            return ProfileSettings(
                searchEngine: values[SettingKey.searchEngine].flatMap(SearchEngine.init(rawValue:)),
                webContent: WebContentSettings(
                    isFraudulentSiteWarningEnabled: values[SettingKey.fraudulentSiteWarning].map { $0 == "1" }
                        ?? defaults.isFraudulentSiteWarningEnabled,
                    isAutoplayingSoundAllowed: values[SettingKey.autoplayingSound].map { $0 == "1" }
                        ?? defaults.isAutoplayingSoundAllowed
                )
            )
        }
    }

    public func save(_ settings: ProfileSettings) throws {
        try queue.write { db in try Self.write(settings, db) }
    }

    /// Saves what changed of the Tabs and the settings in one transaction.
    public func save(_ session: SavedSession?, _ settings: ProfileSettings?) async throws {
        try await queue.write { db in
            if let session { try Self.write(session, db) }
            if let settings { try Self.write(settings, db) }
        }
    }

    private static let activeSpaceKey = "active_space_id"

    private enum SettingKey {
        static let searchEngine = "search_engine"
        static let fraudulentSiteWarning = "web.fraudulent_site_warning"
        static let autoplayingSound = "web.autoplaying_sound"
    }

    private static func write(_ settings: ProfileSettings, _ db: Database) throws {
        if let engine = settings.searchEngine {
            try db.execute(sql: "INSERT OR REPLACE INTO profile_setting (key, value) VALUES (?, ?)",
                           arguments: [SettingKey.searchEngine, engine.rawValue])
        } else {
            try db.execute(sql: "DELETE FROM profile_setting WHERE key = ?", arguments: [SettingKey.searchEngine])
        }
        for (key, value) in [(SettingKey.fraudulentSiteWarning, settings.webContent.isFraudulentSiteWarningEnabled),
                             (SettingKey.autoplayingSound, settings.webContent.isAutoplayingSoundAllowed)] {
            try db.execute(sql: "INSERT OR REPLACE INTO profile_setting (key, value) VALUES (?, ?)",
                           arguments: [key, value ? "1" : "0"])
        }
    }

    private static func tabs(of space: String, _ db: Database) throws -> [TabRecord] {
        try Row.fetchAll(db, sql: """
            SELECT id, url, title, interaction_state, state_os_build FROM tab WHERE space_id = ? ORDER BY position
            """, arguments: [space]).compactMap { row -> TabRecord? in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            return TabRecord(
                id: TabID(rawValue: id),
                address: (row["url"] as String?).flatMap(URL.init(string:)),
                title: row["title"],
                navigationState: row["interaction_state"],
                navigationStateOSBuild: row["state_os_build"]
            )
        }
    }

    /// A Space missing from the session is deleted with its Tabs. A Profile always keeps at least one Space.
    private static func write(_ session: SavedSession, _ db: Database) throws {
        guard !session.spaces.isEmpty else {
            throw DatabaseError(message: "a Profile cannot be saved without a Space")
        }
        let ids = session.spaces.map(\.id.rawValue.uuidString)
        try db.execute(sql: "DELETE FROM tab")
        try db.execute(sql: "DELETE FROM space WHERE id NOT IN (\(databaseQuestionMarks(count: ids.count)))",
                       arguments: StatementArguments(ids))
        for (position, space) in session.spaces.enumerated() {
            let id = space.id.rawValue.uuidString
            try db.execute(sql: """
                INSERT INTO space (id, position, name, emoji, palette_id, selected_tab_id) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET position = excluded.position, name = excluded.name,
                    emoji = excluded.emoji, palette_id = excluded.palette_id, selected_tab_id = excluded.selected_tab_id
                """, arguments: [id, position, space.name, space.emoji, space.paletteID,
                                 space.selectedTabID?.rawValue.uuidString])
            for (position, tab) in space.tabs.enumerated() {
                try db.execute(sql: """
                    INSERT INTO tab (id, space_id, position, url, title, interaction_state, state_os_build)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, arguments: [tab.id.rawValue.uuidString, id, position, tab.address?.absoluteString, tab.title,
                                     tab.navigationState, tab.navigationStateOSBuild])
            }
        }
        let active = session.activeSpace?.id.rawValue.uuidString
        try db.execute(sql: "INSERT OR REPLACE INTO profile_setting (key, value) VALUES (?, ?)",
                       arguments: [activeSpaceKey, active])
    }
}
