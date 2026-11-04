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

private let homeSpace = SpaceID(rawValue: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!)
private let readingSpace = SpaceID(rawValue: UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!)
private let thirdTab = TabID(rawValue: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!)

private func oneSpace(_ tabs: [TabRecord], selected: TabID? = nil) -> SavedSession {
    SavedSession(spaces: [SpaceRecord(id: homeSpace, name: "Home", emoji: "🏠", tabs: tabs, selectedTabID: selected)],
                 activeSpaceID: homeSpace)
}

private func migrations(_ file: URL) throws -> [String] {
    try DatabaseQueue(path: file.path(percentEncoded: false))
        .read { db in try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier") }
}

private func tabRowCount(_ file: URL) throws -> Int {
    try DatabaseQueue(path: file.path(percentEncoded: false))
        .read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tab") ?? -1 }
}

@Suite struct ProfileDatabaseTests {
    @Test func anEmptyDatabaseIsCreatedWithTheLatestSchemaAndOneActiveEmptySpace() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)

        let saved = try ProfileDatabase(file: file).savedSession()

        let space = try #require(saved.spaces.first)
        #expect(saved.spaces.count == 1)
        #expect(saved.activeSpaceID == space.id)
        #expect(space.name == "Home")
        #expect(space.emoji == "🏠")
        #expect(space.paletteID == nil)
        #expect(space.tabs == [])
        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces", "v4-pinned-tabs-folders"])
    }

    @Test func savedSpacesComeBackInOrderWithTheirTabsSelectionAndTheActiveSpace() throws {
        let root = TemporaryRoot()
        let saved = SavedSession(spaces: [
            SpaceRecord(id: readingSpace, name: "Reading", emoji: "📚", paletteID: "ocean", tabs: [
                TabRecord(id: firstTab, address: URL(string: "https://a.com/x?y=1"), title: "A",
                          navigationState: Data([1, 2, 3]), navigationStateOSBuild: "26A434"),
                TabRecord(id: secondTab, address: URL(string: "https://b.com"), title: nil),
            ], selectedTabID: secondTab),
            SpaceRecord(id: homeSpace, name: "Home", emoji: "🏠", tabs: [TabRecord(id: thirdTab)]),
        ], activeSpaceID: homeSpace)

        try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work)).save(saved)

        #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work)).savedSession() == saved)
    }

    @Test func savingReplacesTheTabsSavedBefore() async throws {
        let root = TemporaryRoot()
        let database = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
        try await database.save(oneSpace([TabRecord(id: firstTab), TabRecord(id: secondTab)], selected: firstTab))

        try await database.save(oneSpace([TabRecord(id: secondTab, address: URL(string: "https://b.com"))]))

        #expect(try database.savedSession() == oneSpace([TabRecord(id: secondTab, address: URL(string: "https://b.com"))]))
    }

    @Test func aSpaceLeftOutOfASaveIsDeletedWithItsTabs() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        let database = try ProfileDatabase(file: file)
        try database.save(SavedSession(spaces: [
            SpaceRecord(id: homeSpace, name: "Home", emoji: "🏠", tabs: [TabRecord(id: firstTab)]),
            SpaceRecord(id: readingSpace, name: "Reading", emoji: "📚",
                        tabs: [TabRecord(id: secondTab), TabRecord(id: thirdTab)]),
        ], activeSpaceID: readingSpace))

        try database.save(oneSpace([TabRecord(id: firstTab)]))

        #expect(try database.savedSession() == oneSpace([TabRecord(id: firstTab)]))
        #expect(try tabRowCount(file) == 1)
    }

    @Test func aSaveWithoutASpaceIsRefusedAndKeepsTheSavedOne() throws {
        let database = try ProfileDatabase.inMemory()
        try database.save(oneSpace([TabRecord(id: firstTab)]))

        #expect(throws: (any Error).self) { try database.save(SavedSession()) }
        #expect(try database.savedSession() == oneSpace([TabRecord(id: firstTab)]))
    }

    @Test func eachProfileHasItsOwnDatabaseFileInItsOwnFolder() throws {
        let root = TemporaryRoot()
        let saved = oneSpace([TabRecord(id: firstTab, address: URL(string: "https://work.example"))], selected: firstTab)

        try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work)).save(saved)
        let other = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: personal))

        #expect(try other.savedSession().spaces.flatMap(\.tabs) == [])
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
        try database.save(oneSpace([TabRecord(id: firstTab)], selected: firstTab))

        #expect(try database.savedSession() == oneSpace([TabRecord(id: firstTab)], selected: firstTab))
    }
}

/// Databases left by earlier schemas, written here literally as their migrations create them, so that a later edit of
/// a migration cannot hide a broken upgrade.
@Suite struct MigrationTests {
    private static let version1 = """
        CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
        INSERT INTO grdb_migrations VALUES ('v1-tabs');
        CREATE TABLE space (id TEXT PRIMARY KEY NOT NULL, position INTEGER NOT NULL, selected_tab_id TEXT);
        INSERT INTO space VALUES ('9A1F0C3E-0000-4000-8000-000000000000', 0, '22222222-2222-4222-8222-222222222222');
        CREATE TABLE tab (
            id TEXT PRIMARY KEY NOT NULL,
            space_id TEXT NOT NULL REFERENCES space(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            url TEXT,
            title TEXT
        );
        CREATE INDEX tab_on_space_id ON tab(space_id);
        """
    private static let version1Tabs = """
        INSERT INTO tab VALUES ('11111111-1111-4111-8111-111111111111', '9A1F0C3E-0000-4000-8000-000000000000',
                                0, 'https://a.com/', 'A');
        INSERT INTO tab VALUES ('22222222-2222-4222-8222-222222222222', '9A1F0C3E-0000-4000-8000-000000000000',
                                1, 'https://b.com/', 'B');
        """
    /// `v2-navigation-state` as it shipped: two columns on `tab`, then Tabs saved with their navigation state.
    private static let version2 = """
        INSERT INTO grdb_migrations VALUES ('v2-navigation-state');
        ALTER TABLE tab ADD COLUMN interaction_state BLOB;
        ALTER TABLE tab ADD COLUMN state_os_build TEXT;
        INSERT INTO tab VALUES ('11111111-1111-4111-8111-111111111111', '9A1F0C3E-0000-4000-8000-000000000000',
                                0, 'https://a.com/', 'A', X'0102', '26A434');
        INSERT INTO tab VALUES ('22222222-2222-4222-8222-222222222222', '9A1F0C3E-0000-4000-8000-000000000000',
                                1, 'https://b.com/', 'B', NULL, NULL);
        """
    /// `v3-spaces` as it shipped.
    private static let version3 = """
        INSERT INTO grdb_migrations VALUES ('v3-spaces');
        ALTER TABLE space ADD COLUMN name TEXT NOT NULL DEFAULT 'Home';
        ALTER TABLE space ADD COLUMN emoji TEXT NOT NULL DEFAULT '🏠';
        ALTER TABLE space ADD COLUMN palette_id TEXT;
        CREATE TABLE profile_setting (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
        INSERT INTO profile_setting VALUES ('active_space_id', '9A1F0C3E-0000-4000-8000-000000000000');
        """
    private static let existingSpace = SpaceID(uuidString: "9A1F0C3E-0000-4000-8000-000000000000")!

    private func write(_ sql: String, at file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DatabaseQueue(path: file.path(percentEncoded: false)).write { db in try db.execute(sql: sql) }
    }

    @Test func aVersion1DatabaseMigratesAndKeepsItsTabsByAddress() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version1Tabs, at: file)

        let database = try ProfileDatabase(file: file)

        #expect(try database.savedSession() == SavedSession(spaces: [
            SpaceRecord(id: Self.existingSpace, name: "Home", emoji: "🏠", tabs: [
                TabRecord(id: firstTab, address: URL(string: "https://a.com/"), title: "A"),
                TabRecord(id: secondTab, address: URL(string: "https://b.com/"), title: "B"),
            ], selectedTabID: secondTab),
        ], activeSpaceID: Self.existingSpace))
    }

    @Test func aVersion2DatabaseUpgradesWithItsTabsInItsFirstSpaceWhichIsActive() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2, at: file)

        let database = try ProfileDatabase(file: file)

        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces", "v4-pinned-tabs-folders"])
        #expect(try database.savedSession() == SavedSession(spaces: [
            SpaceRecord(id: Self.existingSpace, name: "Home", emoji: "🏠", tabs: [
                TabRecord(id: firstTab, address: URL(string: "https://a.com/"), title: "A",
                          navigationState: Data([1, 2]), navigationStateOSBuild: "26A434"),
                TabRecord(id: secondTab, address: URL(string: "https://b.com/"), title: "B"),
            ], selectedTabID: secondTab),
        ], activeSpaceID: Self.existingSpace))
    }

    @Test func anUpgradedVersion2DatabaseSavesNewSpaces() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2, at: file)
        var saved = try ProfileDatabase(file: file).savedSession()
        saved.spaces.append(SpaceRecord(id: readingSpace, name: "Reading", emoji: "📚", tabs: [TabRecord(id: thirdTab)],
                                        selectedTabID: thirdTab))
        saved.activeSpaceID = readingSpace

        try ProfileDatabase(file: file).save(saved)

        #expect(try ProfileDatabase(file: file).savedSession() == saved)
    }

    @Test func aVersion3DatabaseUpgradesWithEveryTabStillPlainAndNoFolder() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2 + Self.version3, at: file)

        let saved = try ProfileDatabase(file: file).savedSession()

        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces", "v4-pinned-tabs-folders"])
        let space = try #require(saved.spaces.first)
        #expect(space.pinned == [])
        #expect(space.tabs.map(\.id) == [firstTab, secondTab])
        #expect(space.tabs.allSatisfy { $0.pinnedAddress == nil })
        #expect(space.selectedTabID == secondTab)
    }

    @Test func aMigratedVersion1DatabaseSavesNavigationState() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version1Tabs, at: file)
        let saved = SavedSession(spaces: [
            SpaceRecord(id: Self.existingSpace, name: "Home", emoji: "🏠", tabs: [
                TabRecord(id: firstTab, address: URL(string: "https://a.com/"), navigationState: Data([7]),
                          navigationStateOSBuild: "26A434"),
            ], selectedTabID: firstTab),
        ], activeSpaceID: Self.existingSpace)

        try ProfileDatabase(file: file).save(saved)

        #expect(try ProfileDatabase(file: file).savedSession() == saved)
    }
}

private let docsFolder = FolderID(rawValue: UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!)
private let notesFolder = FolderID(rawValue: UUID(uuidString: "DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD")!)

@Suite struct PinnedAreaDatabaseTests {
    private func tab(_ id: TabID, _ address: String, pinnedAt: String? = nil) -> TabRecord {
        TabRecord(id: id, address: URL(string: address), pinnedAddress: pinnedAt.flatMap(URL.init(string:)))
    }

    @Test func thePinnedAreaComesBackWithItsFoldersTheirOrderAndWhatTheyHold() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        let pinned: [PinnedItemRecord] = [
            .tab(tab(firstTab, "https://a.com/next", pinnedAt: "https://a.com/")),
            .folder(FolderRecord(id: docsFolder, name: "Docs", isExpanded: false, items: [
                .folder(FolderRecord(id: notesFolder, name: "Notes", items: [
                    .tab(tab(secondTab, "https://b.com/", pinnedAt: "https://b.com/")),
                ])),
                .tab(tab(thirdTab, "https://c.com/", pinnedAt: "https://c.com/")),
            ])),
        ]
        let saved = SavedSession(spaces: [
            SpaceRecord(id: homeSpace, name: "Home", emoji: "🏠", pinned: pinned,
                        tabs: [TabRecord(id: TabID(), address: URL(string: "https://plain.com/"))],
                        selectedTabID: secondTab),
        ], activeSpaceID: homeSpace)

        try ProfileDatabase(file: file).save(saved)

        #expect(try ProfileDatabase(file: file).savedSession() == saved)
    }

    @Test func eachSpaceKeepsItsOwnPinnedAreaAndSavingAgainReplacesIt() throws {
        let database = try ProfileDatabase.inMemory()
        let home = SpaceRecord(id: homeSpace, name: "Home", emoji: "🏠", pinned: [.tab(tab(firstTab, "https://a.com/"))])
        let reading = SpaceRecord(id: readingSpace, name: "Reading", emoji: "📚", pinned: [
            .folder(FolderRecord(id: docsFolder, name: "Docs", items: [.tab(tab(secondTab, "https://b.com/"))])),
        ])
        try database.save(SavedSession(spaces: [home, reading], activeSpaceID: homeSpace))
        #expect(try database.savedSession().spaces == [home, reading])

        let unpinned = SpaceRecord(id: readingSpace, name: "Reading", emoji: "📚", tabs: [tab(secondTab, "https://b.com/")])
        try database.save(SavedSession(spaces: [home, unpinned], activeSpaceID: homeSpace))
        #expect(try database.savedSession().spaces == [home, unpinned])
    }

    @Test func aPlainTabWithAFolderReferenceIsStillReadAsPlain() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try ProfileDatabase(file: file).save(SavedSession(spaces: [
            SpaceRecord(id: homeSpace, name: "Home", emoji: "🏠", pinned: [
                .folder(FolderRecord(id: docsFolder, name: "Docs")),
            ], tabs: [TabRecord(id: firstTab)]),
        ], activeSpaceID: homeSpace))
        try DatabaseQueue(path: file.path(percentEncoded: false)).write { db in
            try db.execute(sql: "UPDATE tab SET folder_id = ?", arguments: [docsFolder.rawValue.uuidString])
        }

        let space = try #require(try ProfileDatabase(file: file).savedSession().spaces.first)

        #expect(space.pinned == [.folder(FolderRecord(id: docsFolder, name: "Docs"))])
        #expect(space.tabs.map(\.id) == [firstTab])
    }

    @Test func deletingASpaceDeletesItsFolders() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        let database = try ProfileDatabase(file: file)
        try database.save(SavedSession(spaces: [
            SpaceRecord(id: homeSpace, name: "Home", emoji: "🏠"),
            SpaceRecord(id: readingSpace, name: "Reading", emoji: "📚", pinned: [
                .folder(FolderRecord(id: docsFolder, name: "Docs")),
            ]),
        ], activeSpaceID: homeSpace))
        try database.save(SavedSession(spaces: [SpaceRecord(id: homeSpace, name: "Home", emoji: "🏠")],
                                       activeSpaceID: homeSpace))

        let count = try DatabaseQueue(path: file.path(percentEncoded: false)).read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM folder") ?? -1
        }
        #expect(count == 0)
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
            .save(oneSpace([TabRecord(id: firstTab)], selected: firstTab))

        let tables = try DatabaseQueue(path: root.layout.appDatabaseFile.path(percentEncoded: false)).read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        }
        #expect(tables == ["grdb_migrations", "profile"])
    }
}
