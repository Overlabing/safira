// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import GRDB
import SafiraCore

/// App-level data, `app.sqlite` at the root of Safira's folder: the list of Profiles. A Profile's own data never
/// lives here.
public final class AppDatabase: Sendable {
    private let queue: DatabaseQueue

    public init(file: URL) throws {
        queue = try .opened(at: file, migrator: Migrations.app)
    }

    /// The Profiles in their order. Only the identifier and the name are kept for now.
    public func profiles() throws -> [Profile] {
        try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT id, name FROM profile ORDER BY position").compactMap { row in
                ProfileID(uuidString: row["id"]).map { Profile(id: $0, name: row["name"]) }
            }
        }
    }

    /// Adds a Profile after the others.
    public func add(_ profile: Profile) throws {
        try queue.write { db in
            let position = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM profile") ?? 0
            try db.execute(sql: "INSERT INTO profile (id, name, position) VALUES (?, ?, ?)",
                           arguments: [profile.id.rawValue.uuidString, profile.name, position])
        }
    }
}
