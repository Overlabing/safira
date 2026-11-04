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

/// Every table with its columns, foreign keys and indexes, by name: two databases with the same schema give the same
/// text whatever order their migrations or hand-written fixtures declared things in.
private func schema(_ file: URL) throws -> [String] {
    try DatabaseQueue(path: file.path(percentEncoded: false)).read { db in
        let tables = try String.fetchAll(db, sql: """
            SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name
            """)
        return try tables.flatMap { table -> [String] in
            let columns = try Row.fetchAll(db, sql: "SELECT name, type, \"notnull\", dflt_value, pk FROM pragma_table_info(?) ORDER BY name",
                                           arguments: [table])
                .map { "\(table).\($0["name"] as String) \($0["type"] as String) \($0["notnull"] as Int) \($0["dflt_value"] as String? ?? "-") \($0["pk"] as Int)" }
            let keys = try Row.fetchAll(db, sql: "SELECT \"from\", \"table\", \"to\", on_delete FROM pragma_foreign_key_list(?) ORDER BY \"from\"",
                                        arguments: [table])
                .map { "\(table) fk \($0["from"] as String)->\($0["table"] as String).\($0["to"] as String? ?? "-") \($0["on_delete"] as String)" }
            let indexes = try String.fetchAll(db, sql: "SELECT name FROM pragma_index_list(?) ORDER BY name", arguments: [table])
                .map { "\(table) index \($0)" }
            return columns + keys + indexes
        }
    }
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
        #expect(space.paletteID == "indigo-blue")
        #expect(space.tabs == [])
        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces", "v4-history", "v5-site-permissions", "v6-pinned-tabs-folders", "v7-downloads", "v8-space-themes", "v9-download-folders"])
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

    @Test func rememberedSitePermissionsComeBackInOrderAfterAReopenAndNeverReachAnotherProfile() throws {
        let root = TemporaryRoot()
        let shop = try #require(SiteOrigin(identifier: "https://shop.example"))
        let meet = try #require(SiteOrigin(identifier: "https://meet.example:8443"))
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let database = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))

        try database.save(SitePermission(origin: meet, kind: .microphone, decision: .allow, decidedAt: at))
        try database.save(SitePermission(origin: meet, kind: .camera, decision: .deny, decidedAt: at))
        try database.save(SitePermission(origin: shop, kind: .location, decision: .allow, decidedAt: at))
        try database.save(SitePermission(origin: meet, kind: .camera, decision: .allow, decidedAt: at.addingTimeInterval(60)))

        let reopened = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
        #expect(try reopened.sitePermissions() == [
            SitePermission(origin: meet, kind: .camera, decision: .allow, decidedAt: at.addingTimeInterval(60)),
            SitePermission(origin: meet, kind: .microphone, decision: .allow, decidedAt: at),
            SitePermission(origin: shop, kind: .location, decision: .allow, decidedAt: at),
        ])
        #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: personal)).sitePermissions() == [])
    }

    @Test func removingSitePermissionsForgetsOnlyTheOnesNamed() throws {
        let database = try ProfileDatabase.inMemory()
        let shop = try #require(SiteOrigin(identifier: "https://shop.example"))
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        try database.save(SitePermission(origin: shop, kind: .camera, decision: .allow, decidedAt: at))
        try database.save(SitePermission(origin: shop, kind: .location, decision: .deny, decidedAt: at))

        try database.removeSitePermission(origin: shop, kind: .camera)
        #expect(try database.sitePermissions().map(\.id) == ["https://shop.example location"])

        try database.removeAllSitePermissions()
        #expect(try database.sitePermissions() == [])
    }

    @Test func downloadsComeBackNewestFirstWithEveryFieldAndNeverReachAnotherProfile() throws {
        let root = TemporaryRoot()
        let database = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
        let older = DownloadRecord(
            id: DownloadID(rawValue: UUID(uuidString: "D0000000-0000-4000-8000-000000000001")!),
            sourceURL: URL(string: "https://files.example/a.zip")!, fileName: "a.zip", fileBookmark: Data([1, 2]),
            state: .completed, receivedBytes: 2048, totalBytes: 2048, startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            finishedAt: Date(timeIntervalSince1970: 1_700_000_050))
        let newer = DownloadRecord(
            id: DownloadID(rawValue: UUID(uuidString: "D0000000-0000-4000-8000-000000000002")!),
            sourceURL: URL(string: "https://files.example/b.iso")!, fileName: "b.iso", state: .cancelled,
            receivedBytes: 512, totalBytes: nil, resumeData: Data([7, 7, 7]),
            startedAt: Date(timeIntervalSince1970: 1_700_000_100), finishedAt: Date(timeIntervalSince1970: 1_700_000_110))

        try database.save(older)
        try database.save(newer)

        let reopened = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
        #expect(try reopened.downloads() == [newer, older])
        #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: personal)).downloads() == [])
    }

    @Test func savingADownloadAgainReplacesItAndRemovingDeletesOnlyTheOnesNamed() throws {
        let database = try ProfileDatabase.inMemory()
        var first = DownloadRecord(sourceURL: URL(string: "https://files.example/a.zip")!, fileName: "a.zip",
                                   startedAt: Date(timeIntervalSince1970: 10))
        let second = DownloadRecord(sourceURL: URL(string: "https://files.example/b.zip")!, fileName: "b.zip",
                                    startedAt: Date(timeIntervalSince1970: 20))
        try database.save(first)
        try database.save(second)

        first.state = .failed
        first.receivedBytes = 99
        try database.save(first)
        #expect(try database.downloads() == [second, first])

        try database.removeDownloads([first.id])
        #expect(try database.downloads() == [second])
        try database.removeDownloads([])
        #expect(try database.downloads() == [second])
    }

    @Test func rememberedAppChoicesShareTheSitePermissionTableWithoutShowingUpAsSitePermissions() throws {
        let root = TemporaryRoot()
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let meet = try #require(SiteOrigin(identifier: "https://meet.example"))
        let database = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
        try database.save(SitePermission(origin: meet, kind: .camera, decision: .allow, decidedAt: at))
        try database.save(AppLinkChoice(scheme: try #require(URLScheme("slack")), decision: .allow, decidedAt: at))
        try database.save(AppLinkChoice(scheme: try #require(URLScheme("mailto")), decision: .deny, decidedAt: at))
        try database.save(AppLinkChoice(scheme: try #require(URLScheme("slack")), decision: .deny,
                                        decidedAt: at.addingTimeInterval(60)))

        let reopened = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
        #expect(try reopened.appLinkChoices() == [
            AppLinkChoice(scheme: try #require(URLScheme("mailto")), decision: .deny, decidedAt: at),
            AppLinkChoice(scheme: try #require(URLScheme("slack")), decision: .deny, decidedAt: at.addingTimeInterval(60)),
        ])
        #expect(try reopened.sitePermissions().map(\.id) == ["https://meet.example camera"])
        #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: personal)).appLinkChoices() == [])

        try reopened.removeAppLinkChoice(for: try #require(URLScheme("mailto")))
        #expect(try reopened.appLinkChoices().map(\.scheme.rawValue) == ["slack"])
        #expect(try reopened.sitePermissions().count == 1)

        try reopened.removeAllSitePermissions()
        #expect(try reopened.appLinkChoices() == [])
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
    /// `v4-history` as it shipped: the visits and the external-content full-text index kept in step by triggers.
    private static let version4 = """
        INSERT INTO grdb_migrations VALUES ('v4-history');
        CREATE TABLE history_visit (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            host TEXT NOT NULL,
            title TEXT,
            visited_at DOUBLE NOT NULL
        );
        CREATE INDEX history_visit_on_url ON history_visit(url);
        CREATE INDEX history_visit_on_visited_at ON history_visit(visited_at);
        CREATE VIRTUAL TABLE history_visit_search USING fts5(
            title, url, content='history_visit', content_rowid='id', tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER history_visit_search_ai AFTER INSERT ON history_visit BEGIN
            INSERT INTO history_visit_search(rowid, title, url) VALUES (new.id, new.title, new.url);
        END;
        CREATE TRIGGER history_visit_search_ad AFTER DELETE ON history_visit BEGIN
            INSERT INTO history_visit_search(history_visit_search, rowid, title, url)
            VALUES ('delete', old.id, old.title, old.url);
        END;
        CREATE TRIGGER history_visit_search_au AFTER UPDATE ON history_visit BEGIN
            INSERT INTO history_visit_search(history_visit_search, rowid, title, url)
            VALUES ('delete', old.id, old.title, old.url);
            INSERT INTO history_visit_search(rowid, title, url) VALUES (new.id, new.title, new.url);
        END;
        INSERT INTO history_visit (url, host, title, visited_at) VALUES ('https://a.com/', 'a.com', 'Alpha', 1000);
        """
    /// `v5-site-permissions` as it shipped, with one remembered decision.
    private static let version5 = """
        INSERT INTO grdb_migrations VALUES ('v5-site-permissions');
        CREATE TABLE site_permission (
            origin TEXT NOT NULL,
            kind TEXT NOT NULL,
            decision TEXT NOT NULL,
            decided_at DOUBLE NOT NULL,
            PRIMARY KEY (origin, kind)
        );
        INSERT INTO site_permission VALUES ('https://meet.example', 'camera', 'allow', 1700000000);
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
            SpaceRecord(id: Self.existingSpace, name: "Home", emoji: "🏠", paletteID: "indigo-blue", tabs: [
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

        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces", "v4-history", "v5-site-permissions", "v6-pinned-tabs-folders", "v7-downloads", "v8-space-themes", "v9-download-folders"])
        #expect(try database.savedSession() == SavedSession(spaces: [
            SpaceRecord(id: Self.existingSpace, name: "Home", emoji: "🏠", paletteID: "indigo-blue", tabs: [
                TabRecord(id: firstTab, address: URL(string: "https://a.com/"), title: "A",
                          navigationState: Data([1, 2]), navigationStateOSBuild: "26A434"),
                TabRecord(id: secondTab, address: URL(string: "https://b.com/"), title: "B"),
            ], selectedTabID: secondTab),
        ], activeSpaceID: Self.existingSpace))
    }

    /// `v3-spaces` as it shipped: a named Space with an emoji, the active Space remembered, and one saved setting.
    private static let version3 = """
        INSERT INTO grdb_migrations VALUES ('v3-spaces');
        ALTER TABLE space ADD COLUMN name TEXT NOT NULL DEFAULT 'Home';
        ALTER TABLE space ADD COLUMN emoji TEXT NOT NULL DEFAULT '🏠';
        ALTER TABLE space ADD COLUMN palette_id TEXT;
        CREATE TABLE profile_setting (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
        INSERT INTO profile_setting VALUES ('active_space_id', '9A1F0C3E-0000-4000-8000-000000000000');
        INSERT INTO profile_setting VALUES ('search_engine', 'kagi');
        """

    @Test func aVersion3DatabaseUpgradesWithNoRememberedPermissionAndKeepsItsSettings() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2 + Self.version3, at: file)

        let database = try ProfileDatabase(file: file)

        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces", "v4-history", "v5-site-permissions", "v6-pinned-tabs-folders", "v7-downloads", "v8-space-themes", "v9-download-folders"])
        #expect(try database.sitePermissions() == [])
        #expect(try database.settings().searchEngine == .kagi)
        #expect(try database.savedSession().spaces.flatMap(\.tabs).count == 2)
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

    @Test func theSpacesSavedBeforeThemesTakeThePalettesInTurnAndKeepAnyThemeAlreadyChosen() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2 + Self.version3 + """
            INSERT INTO space (id, position, name, emoji, palette_id) VALUES ('AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA', 1, 'Reading', '📚', NULL);
            INSERT INTO space (id, position, name, emoji, palette_id) VALUES ('BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB', 2, 'Music', '🎵', 'ocean');
            INSERT INTO space (id, position, name, emoji, palette_id) VALUES ('CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC', 9, 'Far', '🌍', NULL);
            """, at: file)

        let saved = try ProfileDatabase(file: file).savedSession()

        #expect(try migrations(file).last == "v9-download-folders")
        #expect(saved.spaces.map(\.name) == ["Home", "Reading", "Music", "Far"])
        #expect(saved.spaces.map(\.paletteID) == ["indigo-blue", "orange-pink", "ocean", "teal-green"])
    }

    @Test func aThemeChosenForASpaceComesBackAfterAReopen() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        var saved = try ProfileDatabase(file: file).savedSession()
        saved.spaces.append(SpaceRecord(id: readingSpace, name: "Reading", emoji: "📚", paletteID: "mint-cyan"))
        saved.spaces[0].paletteID = "brown-yellow"
        try ProfileDatabase(file: file).save(saved)

        #expect(try ProfileDatabase(file: file).savedSession().spaces.map(\.paletteID) == ["brown-yellow", "mint-cyan"])
    }

    @Test func aVersion3DatabaseUpgradesWithEveryTabStillPlainAndNoFolder() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2 + Self.version3, at: file)

        let saved = try ProfileDatabase(file: file).savedSession()

        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces", "v4-history", "v5-site-permissions", "v6-pinned-tabs-folders", "v7-downloads", "v8-space-themes", "v9-download-folders"])
        let space = try #require(saved.spaces.first)
        #expect(space.pinned == [])
        #expect(space.tabs.map(\.id) == [firstTab, secondTab])
        #expect(space.tabs.allSatisfy { $0.pinnedAddress == nil })
        #expect(space.selectedTabID == secondTab)
    }

    @Test func aVersion4DatabaseUpgradesKeepingItsTabsPlainItsHistoryAndAbleToPinThem() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2 + Self.version3 + Self.version4, at: file)

        let database = try ProfileDatabase(file: file)
        let saved = try database.savedSession()

        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces", "v4-history", "v5-site-permissions", "v6-pinned-tabs-folders", "v7-downloads", "v8-space-themes", "v9-download-folders"])
        let space = try #require(saved.spaces.first)
        #expect(space.pinned == [])
        #expect(space.tabs.map(\.id) == [firstTab, secondTab])
        #expect(space.tabs.allSatisfy { $0.pinnedAddress == nil })
        #expect(space.selectedTabID == secondTab)
        let visits = try DatabaseQueue(path: file.path(percentEncoded: false)).read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM history_visit_search WHERE history_visit_search MATCH 'alpha'")
        }
        #expect(visits == 1)

        var pinned = space
        pinned.pinned = [.folder(FolderRecord(id: docsFolder, name: "Docs", items: [
            .tab(TabRecord(id: firstTab, address: URL(string: "https://a.com/"), title: "A",
                           pinnedAddress: URL(string: "https://a.com/"))),
        ]))]
        pinned.tabs = [space.tabs[1]]
        let session = SavedSession(spaces: [pinned], activeSpaceID: Self.existingSpace)
        try database.save(session)
        #expect(try ProfileDatabase(file: file).savedSession() == session)
    }

    private static let latestMigrations = ["v1-tabs", "v2-navigation-state", "v3-spaces", "v4-history", "v5-site-permissions",
                                           "v6-pinned-tabs-folders", "v7-downloads", "v8-space-themes"]

    /// What every later feature needs from a database that was left by an older schema: the same tables as a fresh one,
    /// and a working history, site permissions, Pinned tabs, downloads and Space themes.
    private func useEveryLaterFeature(of file: URL, in root: TemporaryRoot) async throws {
        let fresh = root.layout.profileDatabaseFile(for: personal)
        _ = try ProfileDatabase(file: fresh)
        #expect(try schema(file) == schema(fresh))
        #expect(try migrations(file) == Self.latestMigrations)

        let database = try ProfileDatabase(file: file)
        try await database.recordVisit(to: URL(string: "https://c.com/")!, at: Date(timeIntervalSince1970: 2000))
        try await database.setTitle("Gamma Café", ofLatestVisitTo: URL(string: "https://c.com/")!)
        #expect(try await database.searchHistory("cafe", limit: 10).map(\.title) == ["Gamma Café"])
        try await database.clearHistory(since: Date(timeIntervalSince1970: 2000))
        #expect(try await database.searchHistory("cafe", limit: 10).isEmpty)

        let meet = try #require(SiteOrigin(identifier: "https://meet.example"))
        let permission = SitePermission(origin: meet, kind: .camera, decision: .allow,
                                        decidedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try database.save(permission)
        #expect(try database.sitePermissions() == [permission])

        let download = DownloadRecord(sourceURL: URL(string: "https://files.example/a.zip")!, fileName: "a.zip",
                                      startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try database.save(download)
        #expect(try database.downloads() == [download])

        var session = try database.savedSession()
        var space = try #require(session.spaces.first)
        #expect(space.paletteID == "indigo-blue")
        let pinnedTab = TabRecord(id: firstTab, address: URL(string: "https://a.com/"), title: "A",
                                  pinnedAddress: URL(string: "https://a.com/"))
        space.pinned = [.folder(FolderRecord(id: docsFolder, name: "Docs", items: [.tab(pinnedTab)]))]
        space.tabs = space.tabs.filter { $0.id != firstTab }
        session.spaces = [space]
        try await database.save(session)
        #expect(try ProfileDatabase(file: file).savedSession() == session)
    }

    @Test func aVersion3DatabaseUpgradesToTheLatestSchemaKeepingItsSettingAndTabsAndGainingEveryLaterFeature() async throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2 + Self.version3, at: file)

        let kept = try ProfileDatabase(file: file)
        #expect(try kept.settings().searchEngine == .kagi)
        #expect(try kept.savedSession().spaces.flatMap(\.tabs).map(\.id) == [firstTab, secondTab])

        try await useEveryLaterFeature(of: file, in: root)
    }

    @Test func aVersion4DatabaseUpgradesToTheLatestSchemaKeepingItsHistoryAndGainingEveryLaterFeature() async throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2 + Self.version3 + Self.version4, at: file)

        let kept = try ProfileDatabase(file: file)
        #expect(try await kept.searchHistory("alpha", limit: 10).map(\.title) == ["Alpha"])
        #expect(try kept.savedSession().spaces.flatMap(\.tabs).map(\.id) == [firstTab, secondTab])

        try await useEveryLaterFeature(of: file, in: root)
    }

    @Test func aVersion5DatabaseUpgradesKeepingItsTabAndSitePermissionAndEndsWithTheSchemaOfAFreshDatabase() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2 + Self.version3 + Self.version4 + Self.version5, at: file)

        let database = try ProfileDatabase(file: file)
        let saved = try database.savedSession()

        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces", "v4-history", "v5-site-permissions", "v6-pinned-tabs-folders", "v7-downloads", "v8-space-themes", "v9-download-folders"])
        let space = try #require(saved.spaces.first)
        #expect(space.pinned == [])
        #expect(space.tabs.map(\.id) == [firstTab, secondTab])
        #expect(space.tabs.allSatisfy { $0.pinnedAddress == nil })
        let meet = try #require(SiteOrigin(identifier: "https://meet.example"))
        #expect(try database.sitePermissions() == [
            SitePermission(origin: meet, kind: .camera, decision: .allow, decidedAt: Date(timeIntervalSince1970: 1_700_000_000)),
        ])

        let fresh = root.layout.profileDatabaseFile(for: personal)
        _ = try ProfileDatabase(file: fresh)
        #expect(try schema(file) == schema(fresh))
    }

    /// `v6-pinned-tabs-folders` as it shipped: Folders, and the pin columns on `tab`, with one pinned Tab in a Folder.
    private static let version6 = """
        INSERT INTO grdb_migrations VALUES ('v6-pinned-tabs-folders');
        CREATE TABLE folder (
            id TEXT PRIMARY KEY NOT NULL,
            space_id TEXT NOT NULL REFERENCES space(id) ON DELETE CASCADE,
            parent_folder_id TEXT REFERENCES folder(id) ON DELETE CASCADE,
            name TEXT NOT NULL,
            position INTEGER NOT NULL,
            is_expanded BOOLEAN NOT NULL DEFAULT 1
        );
        CREATE INDEX folder_on_space_id ON folder(space_id);
        ALTER TABLE tab ADD COLUMN folder_id TEXT REFERENCES folder(id) ON DELETE CASCADE;
        ALTER TABLE tab ADD COLUMN is_pinned BOOLEAN NOT NULL DEFAULT 0;
        ALTER TABLE tab ADD COLUMN pinned_url TEXT;
        INSERT INTO folder VALUES ('CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC', '9A1F0C3E-0000-4000-8000-000000000000', NULL, 'Docs', 0, 1);
        UPDATE tab SET is_pinned = 1, folder_id = 'CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC', pinned_url = 'https://a.com/'
            WHERE id = '11111111-1111-4111-8111-111111111111';
        """

    @Test func aVersion6DatabaseUpgradesWithNoDownloadAndKeepsItsPinnedTabAndFolder() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2 + Self.version3 + Self.version4 + Self.version5 + Self.version6, at: file)

        let database = try ProfileDatabase(file: file)

        #expect(try migrations(file) == ["v1-tabs", "v2-navigation-state", "v3-spaces", "v4-history", "v5-site-permissions", "v6-pinned-tabs-folders", "v7-downloads", "v8-space-themes", "v9-download-folders"])
        #expect(try database.downloads() == [])
        let space = try #require(try database.savedSession().spaces.first)
        #expect(space.pinned.count == 1)
        #expect(space.tabs.map(\.id) == [secondTab])
        let download = DownloadRecord(sourceURL: URL(string: "https://files.example/a.zip")!, fileName: "a.zip",
                                      startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try database.save(download)
        #expect(try ProfileDatabase(file: file).downloads() == [download])

        let fresh = root.layout.profileDatabaseFile(for: personal)
        _ = try ProfileDatabase(file: fresh)
        #expect(try schema(file) == schema(fresh))
    }

    @Test func aVersion5DatabaseCanPinItsTabAndKeepsThePinAfterReopening() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version2 + Self.version3 + Self.version4 + Self.version5, at: file)
        var session = try ProfileDatabase(file: file).savedSession()
        var space = try #require(session.spaces.first)
        let pinnedTab = TabRecord(id: firstTab, address: URL(string: "https://a.com/"), title: "A",
                                  pinnedAddress: URL(string: "https://a.com/"))
        space.pinned = [.folder(FolderRecord(id: docsFolder, name: "Docs", items: [.tab(pinnedTab)]))]
        space.tabs = space.tabs.filter { $0.id != firstTab }
        session.spaces = [space]

        try ProfileDatabase(file: file).save(session)

        #expect(try ProfileDatabase(file: file).savedSession() == session)
    }

    @Test func aMigratedVersion1DatabaseSavesNavigationState() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        try write(Self.version1 + Self.version1Tabs, at: file)
        let saved = SavedSession(spaces: [
            SpaceRecord(id: Self.existingSpace, name: "Home", emoji: "🏠", paletteID: "indigo-blue", tabs: [
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

        #expect(try database.profiles() == [Profile(id: work, name: "Default", symbol: "👤", paletteID: "indigo-blue")])
        #expect(try database.lastActiveProfileID() == work)
        #expect(try migrations(file) == ["v1-profiles", "v2-profile-details", "v3-onboarding", "v4-profile-palettes"])
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

    @Test func onboardingIsNotPendingUntilALaunchMarksItAndItsMarkSurvivesTheActiveProfileBeingRemembered() throws {
        let root = TemporaryRoot()
        let database = try AppDatabase(file: root.layout.appDatabaseFile)
        try database.add(Profile(id: work, name: "Work"))
        #expect(try database.isOnboardingPending() == false)

        try database.setOnboardingPending(true)
        try database.setLastActiveProfileID(work)

        #expect(try AppDatabase(file: root.layout.appDatabaseFile).isOnboardingPending())
        #expect(try database.lastActiveProfileID() == work)
        try database.setOnboardingPending(false)
        #expect(try AppDatabase(file: root.layout.appDatabaseFile).isOnboardingPending() == false)
        #expect(try database.lastActiveProfileID() == work)
    }

    @Test func aProfileListYouAlreadyHadNeverGetsAnOnboarding() throws {
        let root = TemporaryRoot()
        let file = root.layout.appDatabaseFile
        try FileManager.default.createDirectory(at: root.layout.root, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: file.path(percentEncoded: false))
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('v1-profiles');
                INSERT INTO grdb_migrations VALUES ('v2-profile-details');
                CREATE TABLE profile (id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL,
                    symbol TEXT NOT NULL DEFAULT '👤', palette_id TEXT, network_config TEXT,
                    pending_deletion BOOLEAN NOT NULL DEFAULT 0);
                CREATE TABLE app_state (id INTEGER PRIMARY KEY CHECK (id = 1), last_profile_id TEXT);
                INSERT INTO profile (id, name, position) VALUES ('0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A', 'Default', 0);
                INSERT INTO app_state (id, last_profile_id) VALUES (1, '0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A');
                """)
        }
        try queue.close()

        let database = try AppDatabase(file: file)

        #expect(try database.isOnboardingPending() == false)
        #expect(try database.lastActiveProfileID() == work)
    }

    @Test func theProfilesListedBeforePalettesTakeThemInTurnAndKeepAnyThemeAlreadyChosen() throws {
        let root = TemporaryRoot()
        let file = root.layout.appDatabaseFile
        try FileManager.default.createDirectory(at: root.layout.root, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: file.path(percentEncoded: false))
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
                INSERT INTO grdb_migrations VALUES ('v1-profiles');
                INSERT INTO grdb_migrations VALUES ('v2-profile-details');
                INSERT INTO grdb_migrations VALUES ('v3-onboarding');
                CREATE TABLE profile (id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL,
                    symbol TEXT NOT NULL DEFAULT '👤', palette_id TEXT, network_config TEXT,
                    pending_deletion BOOLEAN NOT NULL DEFAULT 0);
                CREATE TABLE app_state (id INTEGER PRIMARY KEY CHECK (id = 1), last_profile_id TEXT,
                    onboarding_pending BOOLEAN NOT NULL DEFAULT 0);
                INSERT INTO profile (id, name, position) VALUES ('0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A', 'Work', 0);
                INSERT INTO profile (id, name, position) VALUES ('7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F', 'Personal', 1);
                INSERT INTO profile (id, name, position, palette_id)
                    VALUES ('11111111-2222-4333-8444-555555555555', 'Family', 2, 'ocean');
                """)
        }
        try queue.close()

        let database = try AppDatabase(file: file)

        #expect(try database.profiles().map(\.paletteID) == ["indigo-blue", "orange-pink", "ocean"])
        #expect(try migrations(file).last == "v4-profile-palettes")
    }

    @Test func aProfilesPaletteComesBackAfterAReopen() throws {
        let root = TemporaryRoot()
        let database = try AppDatabase(file: root.layout.appDatabaseFile)
        try database.add(Profile(id: work, name: "Work", paletteID: "red-orange"))
        try database.add(Profile(id: personal, name: "Personal", paletteID: "purple-pink"))
        try database.update(Profile(id: personal, name: "Personal", paletteID: "teal-green"))

        #expect(try AppDatabase(file: root.layout.appDatabaseFile).profiles().map(\.paletteID) == ["red-orange", "teal-green"])
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
