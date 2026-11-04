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
        // Each Space gets a pinned area. A Folder lives in a Space, inside another Folder or at the top of the area; a Tab
        // is pinned with `is_pinned` and then sits in a Folder or at the top. Pinned items and Folders share one
        // `position` sequence per container. Every Tab that exists stays a plain Tab.
        migrator.registerMigration("v4-pinned-tabs-folders") { db in
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
        return migrator
    }

    static var app: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-profiles") { db in
            try db.create(table: "profile") { table in
                table.primaryKey("id", .text)
                table.column("name", .text).notNull()
                table.column("position", .integer).notNull()
            }
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
