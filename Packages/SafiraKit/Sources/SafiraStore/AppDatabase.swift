// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import GRDB
import SafiraCore

/// App-level data, `app.sqlite` at the root of Safira's folder: the list of Profiles and which one was active. A
/// Profile's own data never lives here.
public final class AppDatabase: Sendable {
    private let queue: DatabaseQueue

    public init(file: URL) throws {
        queue = try .opened(at: file, migrator: Migrations.app)
    }

    /// The Profiles in their order, without those being deleted.
    public func profiles() throws -> [Profile] {
        try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, name, symbol, palette_id FROM profile WHERE NOT pending_deletion ORDER BY position
                """)
                .compactMap { row in
                    ProfileID(uuidString: row["id"]).map {
                        Profile(id: $0, name: row["name"], symbol: row["symbol"], paletteID: row["palette_id"])
                    }
                }
        }
    }

    /// Adds a Profile after the others.
    public func add(_ profile: Profile) throws {
        try queue.write { db in
            let position = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position) + 1, 0) FROM profile") ?? 0
            try db.execute(sql: "INSERT INTO profile (id, name, symbol, palette_id, position) VALUES (?, ?, ?, ?, ?)",
                           arguments: [profile.id.rawValue.uuidString, profile.name, profile.symbol,
                                       profile.paletteID, position])
        }
    }

    /// Saves a Profile's name, symbol and Theme; its place in the list does not change.
    public func update(_ profile: Profile) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE profile SET name = ?, symbol = ?, palette_id = ? WHERE id = ?",
                           arguments: [profile.name, profile.symbol, profile.paletteID,
                                       profile.id.rawValue.uuidString])
        }
    }

    /// Takes a Profile out of the list before its files are erased; it stays recorded until `delete` so that an
    /// erase cut short can be finished.
    public func markForDeletion(_ id: ProfileID) throws {
        try queue.write { db in
            try db.execute(sql: "UPDATE profile SET pending_deletion = 1 WHERE id = ?", arguments: [id.rawValue.uuidString])
            try db.execute(sql: "UPDATE app_state SET last_profile_id = NULL WHERE last_profile_id = ?",
                           arguments: [id.rawValue.uuidString])
        }
    }

    /// The Profiles whose erase has not finished.
    public func profilesPendingDeletion() throws -> [ProfileID] {
        try queue.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM profile WHERE pending_deletion ORDER BY position")
                .compactMap(ProfileID.init(uuidString:))
        }
    }

    /// Forgets a Profile for good, once its folder and data store are erased.
    public func delete(_ id: ProfileID) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM profile WHERE id = ?", arguments: [id.rawValue.uuidString])
            try db.execute(sql: "UPDATE app_state SET last_profile_id = NULL WHERE last_profile_id = ?",
                           arguments: [id.rawValue.uuidString])
        }
    }

    /// The Profile that was active last, if it is still listed.
    public func lastActiveProfileID() throws -> ProfileID? {
        try queue.read { db in
            try String.fetchOne(db, sql: """
                SELECT last_profile_id FROM app_state JOIN profile ON profile.id = app_state.last_profile_id
                """).flatMap(ProfileID.init(uuidString:))
        }
    }

    public func setLastActiveProfileID(_ id: ProfileID) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO app_state (id, last_profile_id) VALUES (1, ?)
                ON CONFLICT (id) DO UPDATE SET last_profile_id = excluded.last_profile_id
                """, arguments: [id.rawValue.uuidString])
        }
    }

    /// Whether the first launch's onboarding has not finished. False for an app that never had one.
    public func isOnboardingPending() throws -> Bool {
        try queue.read { db in
            try Bool.fetchOne(db, sql: "SELECT onboarding_pending FROM app_state WHERE id = 1") ?? false
        }
    }

    public func setOnboardingPending(_ pending: Bool) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT INTO app_state (id, onboarding_pending) VALUES (1, ?)
                ON CONFLICT (id) DO UPDATE SET onboarding_pending = excluded.onboarding_pending
                """, arguments: [pending])
        }
    }
}
