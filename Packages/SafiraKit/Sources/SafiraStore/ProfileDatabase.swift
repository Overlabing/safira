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

    /// Every Space with its Tabs, in sidebar order, and the active Space.
    public func savedSession() throws -> SavedSession {
        try queue.read { db in
            let spaces = try Row.fetchAll(db, sql: """
                SELECT id, name, emoji, palette_id, selected_tab_id FROM space ORDER BY position
                """).compactMap { row -> SpaceRecord? in
                guard let id = SpaceID(uuidString: row["id"]) else { return nil }
                let contents = try Self.contents(of: row["id"], db)
                let selected = (row["selected_tab_id"] as String?).flatMap(UUID.init(uuidString:)).map(TabID.init(rawValue:))
                var space = SpaceRecord(id: id, name: row["name"], emoji: row["emoji"], paletteID: row["palette_id"],
                                        pinned: contents.pinned, tabs: contents.tabs)
                space.selectedTabID = space.allTabs.contains { $0.id == selected } ? selected : nil
                return space
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

    private static let activeSpaceKey = "active_space_id"

    private struct StoredTab {
        let record: TabRecord
        let position: Int
        let isPinned: Bool
        let folder: String?
    }

    private struct StoredFolder {
        let id: String
        let record: FolderID
        let name: String
        let isExpanded: Bool
        let position: Int
        let parent: String?
    }

    /// A Space's Tabs and Folders as the rows hold them, put back into the pinned area and the plain Tabs. A Folder
    /// is rebuilt from the top, so a row that cannot be reached from it (a loop, an unreadable identifier) is left out,
    /// and a plain Tab is never read as a member of a Folder.
    private static func contents(of space: String, _ db: Database) throws -> (pinned: [PinnedItemRecord], tabs: [TabRecord]) {
        let storedTabs = try Row.fetchAll(db, sql: """
            SELECT id, url, title, interaction_state, state_os_build, position, is_pinned, folder_id, pinned_url
            FROM tab WHERE space_id = ? ORDER BY position
            """, arguments: [space]).compactMap { row -> StoredTab? in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            return StoredTab(
                record: TabRecord(
                    id: TabID(rawValue: id),
                    address: (row["url"] as String?).flatMap(URL.init(string:)),
                    title: row["title"],
                    navigationState: row["interaction_state"],
                    navigationStateOSBuild: row["state_os_build"],
                    pinnedAddress: (row["pinned_url"] as String?).flatMap(URL.init(string:))
                ),
                position: row["position"], isPinned: row["is_pinned"], folder: row["folder_id"])
        }
        let storedFolders = try Row.fetchAll(db, sql: """
            SELECT id, name, position, is_expanded, parent_folder_id FROM folder WHERE space_id = ?
            """, arguments: [space]).compactMap { row -> StoredFolder? in
            guard let id = FolderID(uuidString: row["id"]) else { return nil }
            return StoredFolder(id: row["id"], record: id, name: row["name"], isExpanded: row["is_expanded"],
                                position: row["position"], parent: row["parent_folder_id"])
        }
        func items(in container: String?) -> [PinnedItemRecord] {
            let tabs = storedTabs.filter { $0.isPinned && $0.folder == container }
                .map { (position: $0.position, item: PinnedItemRecord.tab($0.record)) }
            let folders = storedFolders.filter { $0.parent == container }.map { folder in
                (position: folder.position, item: PinnedItemRecord.folder(
                    FolderRecord(id: folder.record, name: folder.name, isExpanded: folder.isExpanded,
                                 items: items(in: folder.id))))
            }
            return (tabs + folders).sorted { $0.position < $1.position }.map(\.item)
        }
        return (items(in: nil), storedTabs.filter { !$0.isPinned }.map(\.record))
    }

    /// A Space missing from the session is deleted with its Tabs. A Profile always keeps at least one Space.
    private static func write(_ session: SavedSession, _ db: Database) throws {
        guard !session.spaces.isEmpty else {
            throw DatabaseError(message: "a Profile cannot be saved without a Space")
        }
        let ids = session.spaces.map(\.id.rawValue.uuidString)
        try db.execute(sql: "DELETE FROM tab")
        try db.execute(sql: "DELETE FROM folder")
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
            try write(space.pinned, inFolder: nil, of: id, db)
            for (position, tab) in space.tabs.enumerated() {
                try write(tab, at: position, pinnedIn: nil, isPinned: false, of: id, db)
            }
        }
        let active = session.activeSpace?.id.rawValue.uuidString
        try db.execute(sql: "INSERT OR REPLACE INTO profile_setting (key, value) VALUES (?, ?)",
                       arguments: [activeSpaceKey, active])
    }

    /// Folders go in before what they hold, so that the references between rows hold at every step.
    private static func write(_ items: [PinnedItemRecord], inFolder folder: String?, of space: String,
                              _ db: Database) throws {
        for (position, item) in items.enumerated() {
            switch item {
            case .tab(let tab):
                try write(tab, at: position, pinnedIn: folder, isPinned: true, of: space, db)
            case .folder(let record):
                let id = record.id.rawValue.uuidString
                try db.execute(sql: """
                    INSERT INTO folder (id, space_id, parent_folder_id, name, position, is_expanded)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [id, space, folder, record.name, position, record.isExpanded])
                try write(record.items, inFolder: id, of: space, db)
            }
        }
    }

    private static func write(_ tab: TabRecord, at position: Int, pinnedIn folder: String?, isPinned: Bool,
                              of space: String, _ db: Database) throws {
        try db.execute(sql: """
            INSERT INTO tab (id, space_id, position, url, title, interaction_state, state_os_build, folder_id,
                             is_pinned, pinned_url)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [tab.id.rawValue.uuidString, space, position, tab.address?.absoluteString, tab.title,
                             tab.navigationState, tab.navigationStateOSBuild, folder, isPinned,
                             tab.pinnedAddress?.absoluteString])
    }
}
