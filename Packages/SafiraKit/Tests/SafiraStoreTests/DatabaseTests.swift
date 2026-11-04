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
        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces"])
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

        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces"])
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
        #expect(tables == ["app_state", "grdb_migrations", "profile"])
    }

    @Test func aProfileListedBeforeProfilesExistedKeepsItsIdentifierAndBecomesActive() throws {
        let root = TemporaryRoot()
        let file = root.layout.appDatabaseFile
        try FileManager.default.createDirectory(at: root.layout.root, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: file.path(percentEncoded: false))
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('v1-profiles');
                CREATE TABLE profile (id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL);
                INSERT INTO profile VALUES ('0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A', 'Default', 0);
                """)
        }
        try queue.close()

        let database = try AppDatabase(file: file)

        #expect(try database.profiles() == [Profile(id: work, name: "Default", symbol: "👤")])
        #expect(try database.lastActiveProfileID() == work)
        #expect(try migrations(file) == ["v1-profiles", "v2-profile-details"])
    }

    @Test func aRenamedProfileKeepsItsPlaceAndItsNewNameAfterAReopen() throws {
        let root = TemporaryRoot()
        let database = try AppDatabase(file: root.layout.appDatabaseFile)
        try database.add(Profile(id: work, name: "Work"))
        try database.add(Profile(id: personal, name: "Personal"))

        try database.update(Profile(id: work, name: "Office", symbol: "💼", paletteID: "ocean"))

        #expect(try AppDatabase(file: root.layout.appDatabaseFile).profiles() == [
            Profile(id: work, name: "Office", symbol: "💼", paletteID: "ocean"),
            Profile(id: personal, name: "Personal"),
        ])
    }

    @Test func theActiveProfileIsRememberedUntilItIsDeleted() throws {
        let root = TemporaryRoot()
        let database = try AppDatabase(file: root.layout.appDatabaseFile)
        try database.add(Profile(id: work, name: "Work"))
        try database.add(Profile(id: personal, name: "Personal"))
        #expect(try database.lastActiveProfileID() == nil)

        try database.setLastActiveProfileID(personal)
        #expect(try AppDatabase(file: root.layout.appDatabaseFile).lastActiveProfileID() == personal)

        try database.markForDeletion(personal)
        #expect(try database.lastActiveProfileID() == nil)
    }

    @Test func aProfileBeingDeletedLeavesTheListButStaysRecordedUntilItIsErased() throws {
        let root = TemporaryRoot()
        let database = try AppDatabase(file: root.layout.appDatabaseFile)
        try database.add(Profile(id: work, name: "Work"))
        try database.add(Profile(id: personal, name: "Personal"))

        try database.markForDeletion(work)
        #expect(try database.profiles() == [Profile(id: personal, name: "Personal")])
        #expect(try AppDatabase(file: root.layout.appDatabaseFile).profilesPendingDeletion() == [work])

        try database.delete(work)
        #expect(try database.profilesPendingDeletion() == [])
        #expect(try database.profiles() == [Profile(id: personal, name: "Personal")])
    }
}

@Suite struct ProfileSettingsTests {
    @Test func aNewProfileHasNoSearchEngineAndTheDefaultWebContentSettings() throws {
        let root = TemporaryRoot()
        let settings = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work)).settings()
        #expect(settings == ProfileSettings(searchEngine: nil, webContent: WebContentSettings(
            isFraudulentSiteWarningEnabled: true, isAutoplayingSoundAllowed: false)))
    }

    @Test func settingsAreSavedWithTheProfileAndComeBackAfterAReopen() async throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        let saved = ProfileSettings(searchEngine: .kagi, webContent: WebContentSettings(
            isFraudulentSiteWarningEnabled: false, isAutoplayingSoundAllowed: true))

        try await ProfileDatabase(file: file).save(saved)

        #expect(try ProfileDatabase(file: file).settings() == saved)
    }

    @Test func savingTheTabsKeepsTheSettingsAndTheOtherWayRound() throws {
        let root = TemporaryRoot()
        let database = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
        let settings = ProfileSettings(searchEngine: .ecosia)
        try database.save(settings)
        let tabs = oneSpace([TabRecord(id: firstTab)], selected: firstTab)

        try database.save(tabs)
        try database.save(settings)

        #expect(try database.settings() == settings)
        #expect(try database.savedSession() == tabs)
    }

    @Test func oneProfilesSearchEngineIsNotAnotherProfiles() throws {
        let root = TemporaryRoot()
        try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work)).save(ProfileSettings(searchEngine: .google))

        #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: personal)).settings().searchEngine == nil)
    }

    @Test func clearingTheSearchEngineForgetsIt() throws {
        let root = TemporaryRoot()
        let database = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
        try database.save(ProfileSettings(searchEngine: .google))

        try database.save(ProfileSettings(searchEngine: nil))

        #expect(try database.settings().searchEngine == nil)
    }
}
