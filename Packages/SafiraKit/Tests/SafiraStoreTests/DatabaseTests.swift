// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import GRDB
import SafiraCore
import SafiraStore
import Testing

/// A fresh Application Support folder for one test, removed when the test ends.
private final class TemporaryRoot {
    let layout = StoreLayout(root: FileManager.default.temporaryDirectory
        .appending(path: "safira-\(UUID().uuidString)", directoryHint: .isDirectory))

    deinit { try? FileManager.default.removeItem(at: layout.root) }
}

private let work = ProfileID(rawValue: UUID(uuidString: "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A")!)
private let personal = ProfileID(rawValue: UUID(uuidString: "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F")!)
private let firstTab = TabID(rawValue: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)
private let secondTab = TabID(rawValue: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!)

@Suite struct ProfileDatabaseTests {
    @Test func anEmptyDatabaseIsCreatedWithTheLatestSchemaAndNoTabs() throws {
        let root = TemporaryRoot()

        let database = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))

        #expect(try database.savedSession() == SavedSession())
        let migrations = try DatabaseQueue(path: root.layout.profileDatabaseFile(for: work).path(percentEncoded: false))
            .read { db in try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier") }
        #expect(migrations == ["v1-tabs", "v2-navigation-state"])
    }

    @Test func savedTabsComeBackInOrderWithTheirStateAndSelection() throws {
        let root = TemporaryRoot()
        let saved = SavedSession(tabs: [
            TabRecord(id: firstTab, address: URL(string: "https://a.com/x?y=1"), title: "A",
                      navigationState: Data([1, 2, 3]), navigationStateOSBuild: "26A434"),
            TabRecord(id: secondTab, address: URL(string: "https://b.com"), title: nil),
        ], selectedTabID: secondTab)

        try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work)).save(saved)

        #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work)).savedSession() == saved)
    }

    @Test func savingReplacesTheTabsSavedBefore() async throws {
        let root = TemporaryRoot()
        let database = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
        try await database.save(SavedSession(tabs: [TabRecord(id: firstTab), TabRecord(id: secondTab)],
                                             selectedTabID: firstTab))

        try await database.save(SavedSession(tabs: [TabRecord(id: secondTab, address: URL(string: "https://b.com"))]))

        #expect(try database.savedSession()
            == SavedSession(tabs: [TabRecord(id: secondTab, address: URL(string: "https://b.com"))]))
    }

    @Test func eachProfileHasItsOwnDatabaseFileInItsOwnFolder() throws {
        let root = TemporaryRoot()
        let saved = SavedSession(tabs: [TabRecord(id: firstTab, address: URL(string: "https://work.example"))],
                                 selectedTabID: firstTab)

        try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work)).save(saved)
        let other = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: personal))

        #expect(try other.savedSession() == SavedSession())
        #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work)).savedSession() == saved)
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.layout.root.path(percentEncoded: false))
            .filter { $0.hasSuffix(".sqlite") }
            .sorted()
        #expect(files == [
            "Profiles/0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A/profile.sqlite",
            "Profiles/7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F/profile.sqlite",
        ])
    }

    @Test func anInMemoryDatabaseKeepsTabsWhileOpen() throws {
        let database = try ProfileDatabase.inMemory()
        try database.save(SavedSession(tabs: [TabRecord(id: firstTab)], selectedTabID: firstTab))

        #expect(try database.savedSession() == SavedSession(tabs: [TabRecord(id: firstTab)], selectedTabID: firstTab))
    }
}

/// A database left by the first schema, `v1-tabs`, written here literally as that migration creates it, so that
/// a later edit of the migration cannot hide a broken upgrade.
@Suite struct MigrationTests {
    private func writeVersion1(at file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DatabaseQueue(path: file.path(percentEncoded: false)).write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('v1-tabs');
                CREATE TABLE space (id TEXT PRIMARY KEY NOT NULL, position INTEGER NOT NULL, selected_tab_id TEXT);
                INSERT INTO space VALUES ('9A1F0C3E-0000-4000-8000-000000000000', 0,
                                          '22222222-2222-4222-8222-222222222222');
                CREATE TABLE tab (
                    id TEXT PRIMARY KEY NOT NULL,
                    space_id TEXT NOT NULL REFERENCES space(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL,
                    url TEXT,
                    title TEXT
                );
                CREATE INDEX tab_on_space_id ON tab(space_id);
                INSERT INTO tab VALUES ('11111111-1111-4111-8111-111111111111', '9A1F0C3E-0000-4000-8000-000000000000',
                                        0, 'https://a.com/', 'A');
                INSERT INTO tab VALUES ('22222222-2222-4222-8222-222222222222', '9A1F0C3E-0000-4000-8000-000000000000',
                                        1, 'https://b.com/', 'B');
                """)
        }
    }

    @Test func aVersion1DatabaseMigratesAndKeepsItsTabsByAddress() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try writeVersion1(at: file)

        let database = try ProfileDatabase(file: file)

        #expect(try database.savedSession() == SavedSession(tabs: [
            TabRecord(id: firstTab, address: URL(string: "https://a.com/"), title: "A"),
            TabRecord(id: secondTab, address: URL(string: "https://b.com/"), title: "B"),
        ], selectedTabID: secondTab))
    }

    @Test func aMigratedVersion1DatabaseSavesNavigationState() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try writeVersion1(at: file)
        let saved = SavedSession(tabs: [TabRecord(id: firstTab, address: URL(string: "https://a.com/"),
                                                  navigationState: Data([7]), navigationStateOSBuild: "26A434")],
                                 selectedTabID: firstTab)

        try ProfileDatabase(file: file).save(saved)

        #expect(try ProfileDatabase(file: file).savedSession() == saved)
    }
}

@Suite struct AppDatabaseTests {
    @Test func profilesAreKeptInTheOrderTheyWereAdded() throws {
        let root = TemporaryRoot()
        let database = try AppDatabase(file: root.layout.appDatabaseFile)
        #expect(try database.profiles() == [])

        try database.add(Profile(id: work, name: "Work"))
        try database.add(Profile(id: personal, name: "Personal"))

        #expect(try AppDatabase(file: root.layout.appDatabaseFile).profiles()
            == [Profile(id: work, name: "Work"), Profile(id: personal, name: "Personal")])
    }

    @Test func theAppDatabaseHoldsNoTabsOfAnyProfile() throws {
        let root = TemporaryRoot()
        try AppDatabase(file: root.layout.appDatabaseFile).add(Profile(id: work, name: "Work"))
        try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
            .save(SavedSession(tabs: [TabRecord(id: firstTab)], selectedTabID: firstTab))

        let tables = try DatabaseQueue(path: root.layout.appDatabaseFile.path(percentEncoded: false)).read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        }
        #expect(tables == ["grdb_migrations", "profile"])
    }
}
