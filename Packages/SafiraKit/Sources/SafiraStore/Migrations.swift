// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import GRDB

// A migration is never edited once it has shipped: a change to the schema is a new, named migration.
enum Migrations {
    static var profile: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // One Space per Profile until Spaces exist; the database already holds it so that Tabs belong to a Space.
        migrator.registerMigration("v1-tabs") { db in
            try db.create(table: "space") { table in
                table.primaryKey("id", .text)
                table.column("position", .integer).notNull()
                table.column("selected_tab_id", .text)
            }
            try db.execute(sql: "INSERT INTO space (id, position) VALUES (?, 0)", arguments: [UUID().uuidString])
            try db.create(table: "tab") { table in
                table.primaryKey("id", .text)
                table.column("space_id", .text).notNull().indexed().references("space", onDelete: .cascade)
                table.column("position", .integer).notNull()
                table.column("url", .text)
                table.column("title", .text)
            }
        }
        migrator.registerMigration("v2-navigation-state") { db in
            try db.alter(table: "tab") { table in
                table.add(column: "interaction_state", .blob)
                table.add(column: "state_os_build", .text)
            }
        }
        // Spaces get a name and an emoji, the Theme slot of #10, and the Profile remembers its active Space. The Space
        // the Profile already has keeps its Tabs and becomes the active one.
        migrator.registerMigration("v3-spaces") { db in
            try db.alter(table: "space") { table in
                table.add(column: "name", .text).notNull().defaults(to: "Home")
                table.add(column: "emoji", .text).notNull().defaults(to: "🏠")
                table.add(column: "palette_id", .text)
            }
            try db.create(table: "profile_setting") { table in
                table.primaryKey("key", .text)
                table.column("value", .text).notNull()
            }
            try db.execute(sql: """
                INSERT INTO profile_setting (key, value)
                SELECT 'active_space_id', id FROM space ORDER BY position LIMIT 1
                """)
        }
        // The Profile's history, searchable with letter case and accents ignored. The index is kept in step with the
        // table by triggers, so a title set after the visit is searchable too.
        migrator.registerMigration("v4-history") { db in
            try db.create(table: "history_visit") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("url", .text).notNull().indexed()
                table.column("host", .text).notNull()
                table.column("title", .text)
                table.column("visited_at", .double).notNull().indexed()
            }
            try db.create(virtualTable: "history_visit_search", using: FTS5()) { table in
                table.synchronize(withTable: "history_visit")
                table.tokenizer = .unicode61(diacritics: .remove)
                table.column("title")
                table.column("url")
            }
        }
        // What a site may use, per Profile: camera, microphone and location, and later the apps a link may open.
        migrator.registerMigration("v5-site-permissions") { db in
            try db.create(table: "site_permission") { table in
                table.column("origin", .text).notNull()
                table.column("kind", .text).notNull()
                table.column("decision", .text).notNull()
                table.column("decided_at", .double).notNull()
                table.primaryKey(["origin", "kind"])
            }
        }
        // Each Space gets a pinned area. A Folder lives in a Space, inside another Folder or at the top of the area; a Tab
        // is pinned with `is_pinned` and then sits in a Folder or at the top. Pinned items and Folders share one
        // `position` sequence per container. Every Tab that exists stays a plain Tab.
        migrator.registerMigration("v6-pinned-tabs-folders") { db in
            try db.create(table: "folder") { table in
                table.primaryKey("id", .text)
                table.column("space_id", .text).notNull().indexed().references("space", onDelete: .cascade)
                table.column("parent_folder_id", .text).references("folder", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("is_expanded", .boolean).notNull().defaults(to: true)
            }
            try db.alter(table: "tab") { table in
                table.add(column: "folder_id", .text).references("folder", onDelete: .cascade)
                table.add(column: "is_pinned", .boolean).notNull().defaults(to: false)
                table.add(column: "pinned_url", .text)
            }
        }
        // The Profile's downloads: what the download manager lists, and what a cancelled or interrupted transfer needs
        // to be started again. A transfer that was running when Safira quit is read back as failed.
        migrator.registerMigration("v7-downloads") { db in
            try db.create(table: "download") { table in
                table.primaryKey("id", .text)
                table.column("source_url", .text).notNull()
                table.column("file_name", .text).notNull()
                table.column("file_bookmark", .blob)
                table.column("state", .text).notNull()
                table.column("bytes", .integer).notNull().defaults(to: 0)
                table.column("total_bytes", .integer)
                table.column("resume_data", .blob)
                table.column("started_at", .double).notNull().indexed()
                table.column("finished_at", .double)
            }
        }
        // Every Space has a Theme from the Palette (#10). The Spaces saved so far have none, so they take the Palette's
        // Themes in turn by position, which is what the Space editor would have offered them. The ids are written out:
        // a migration must not move when the Palette does.
        migrator.registerMigration("v8-space-themes") { db in
            try db.execute(sql: "UPDATE space SET palette_id = \(Self.paletteByPosition) WHERE palette_id IS NULL")
        }
        return migrator
    }

    /// An SQL expression that picks one of the Palette's Theme ids by the row's `position`, cycling.
    private static let paletteByPosition = """
        CASE position % 7 WHEN 0 THEN 'indigo-blue' WHEN 1 THEN 'orange-pink' WHEN 2 THEN 'teal-green' \
        WHEN 3 THEN 'red-orange' WHEN 4 THEN 'purple-pink' WHEN 5 THEN 'mint-cyan' ELSE 'brown-yellow' END
        """

    static var app: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-profiles") { db in
            try db.create(table: "profile") { table in
                table.primaryKey("id", .text)
                table.column("name", .text).notNull()
                table.column("position", .integer).notNull()
            }
        }
        // A Profile gets the symbol and Theme slot that mark it in the sidebar, and the reserved network configuration
        // (docs/scope-v1.md §3); a deletion is recorded until the Profile's files are gone; the app remembers which Profile was active. Profiles already listed keep their
        // identifier, so their folder and data store stay theirs.
        migrator.registerMigration("v2-profile-details") { db in
            try db.alter(table: "profile") { table in
                table.add(column: "symbol", .text).notNull().defaults(to: "👤")
                table.add(column: "palette_id", .text)
                table.add(column: "network_config", .text)
                // Set while a deleted Profile's files are being erased, so that an erase cut short finishes at the
                // next launch instead of leaving a Profile half erased.
                table.add(column: "pending_deletion", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "app_state") { table in
                table.primaryKey("id", .integer).check { $0 == 1 }
                table.column("last_profile_id", .text)
            }
            try db.execute(sql: "INSERT INTO app_state (id, last_profile_id) SELECT 1, id FROM profile ORDER BY position LIMIT 1")
        }
        // Set when a first launch creates the first Profile and cleared when onboarding finishes, so that an onboarding cut
        // short is offered again, and a Profile list that already existed never gets one.
        migrator.registerMigration("v3-onboarding") { db in
            try db.alter(table: "app_state") { table in
                table.add(column: "onboarding_pending", .boolean).notNull().defaults(to: false)
            }
        }
        // Every Profile has a Palette Theme (#10), which tints the sidebar and the Dock icon. The Profiles listed so far
        // have none, so they take the Palette's Themes in turn by position, which keeps them apart.
        migrator.registerMigration("v4-profile-palettes") { db in
            try db.execute(sql: "UPDATE profile SET palette_id = \(Self.paletteByPosition) WHERE palette_id IS NULL")
        }
        return migrator
    }
}

extension DatabaseQueue {
    /// Opens the database file, creating its folder, and brings its schema up to date.
    static func opened(at file: URL, migrator: DatabaseMigrator) throws -> DatabaseQueue {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: file.path(percentEncoded: false))
        try migrator.migrate(queue)
        return queue
    }
}
