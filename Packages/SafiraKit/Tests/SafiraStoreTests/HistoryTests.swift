// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraStore
import Testing

private func url(_ string: String) -> URL { URL(string: string)! }

private func titles(_ entries: [HistoryEntry]) -> [String?] { entries.map(\.title) }

/// The Profile's history and its full-text search.
@Suite struct HistoryTests {
    private func database(visiting pages: [(String, String?)]) async throws -> ProfileDatabase {
        let database = try ProfileDatabase.inMemory()
        for (address, title) in pages {
            try await database.recordVisit(to: url(address))
            if let title { try await database.setTitle(title, ofLatestVisitTo: url(address)) }
        }
        return database
    }

    @Test func aWordPrefixOfTheTitleFindsThePage() async throws {
        let database = try await database(visiting: [("https://swift.org/", "Swift Programming Language")])

        let found = try await database.searchHistory("prog", limit: 10)

        #expect(found == [HistoryEntry(url: url("https://swift.org/"), title: "Swift Programming Language")])
    }

    @Test func accentsAndLetterCaseAreIgnoredInBothDirections() async throws {
        let database = try await database(visiting: [
            ("https://example.com/menu", "Café Crème"),
            ("https://example.com/ete", "Plage d’été"),
        ])

        #expect(titles(try await database.searchHistory("cafe", limit: 10)) == ["Café Crème"])
        #expect(titles(try await database.searchHistory("CAFÉ", limit: 10)) == ["Café Crème"])
        #expect(titles(try await database.searchHistory("crème", limit: 10)) == ["Café Crème"])
        #expect(titles(try await database.searchHistory("ETE", limit: 10)) == ["Plage d’été"])
        #expect(titles(try await database.searchHistory("été", limit: 10)) == ["Plage d’été"])
    }

    @Test func theAddressIsSearchableToo() async throws {
        let database = try await database(visiting: [("https://docs.example.com/guide/install", nil)])

        #expect(try await database.searchHistory("guide", limit: 10).map(\.url) == [url("https://docs.example.com/guide/install")])
        #expect(try await database.searchHistory("DOCS.example", limit: 10).count == 1)
    }

    @Test func everyWordMustMatch() async throws {
        let database = try await database(visiting: [
            ("https://a.example/", "Swift Concurrency"),
            ("https://b.example/", "Swift Packages"),
        ])

        #expect(titles(try await database.searchHistory("swift conc", limit: 10)) == ["Swift Concurrency"])
        #expect(try await database.searchHistory("swift rust", limit: 10).isEmpty)
    }

    @Test func aPageVisitedTwiceIsListedOnceWithItsLatestTitleAndTheMostRecentPageFirst() async throws {
        let database = try await database(visiting: [
            ("https://news.example/", "News"),
            ("https://news.example/story", "Story one"),
            ("https://news.example/", "News (2 new)"),
        ])

        let found = try await database.searchHistory("news", limit: 10)

        #expect(found.map(\.url.absoluteString) == ["https://news.example/", "https://news.example/story"])
        #expect(titles(found) == ["News (2 new)", "Story one"])
    }

    @Test func theLimitKeepsTheMostRecentPages() async throws {
        let database = try await database(visiting: (1...5).map { ("https://site.example/\($0)", "Page \($0)") })

        #expect(titles(try await database.searchHistory("page", limit: 2)) == ["Page 5", "Page 4"])
    }

    @Test func aTitleSetAfterTheVisitIsSearchableAndOneNeverSetLeavesTheAddress() async throws {
        let database = try ProfileDatabase.inMemory()
        try await database.recordVisit(to: url("https://late.example/path"))
        #expect(try await database.searchHistory("renamed", limit: 10).isEmpty)

        try await database.setTitle("Renamed later", ofLatestVisitTo: url("https://late.example/path"))

        #expect(titles(try await database.searchHistory("renamed", limit: 10)) == ["Renamed later"])
        #expect(try await database.searchHistory("late.example", limit: 10).first?.title == "Renamed later")
    }

    @Test func textWithNothingToSearchForFindsNothing() async throws {
        let database = try await database(visiting: [("https://a.example/", "A")])

        #expect(try await database.searchHistory("", limit: 10).isEmpty)
        #expect(try await database.searchHistory("   ", limit: 10).isEmpty)
        #expect(try await database.searchHistory("\"*()", limit: 10).isEmpty)
        #expect(try await database.searchHistory("a", limit: 0).isEmpty)
    }

    @Test func onlyWebAddressesAreHistory() async throws {
        let database = try ProfileDatabase.inMemory()
        for address in ["about:blank", "file:///Users/me/notes.txt", "data:text/html,hello", "javascript:alert(1)"] {
            try await database.recordVisit(to: url(address))
        }

        #expect(try await database.searchHistory("blank notes hello alert", limit: 10).isEmpty)
        #expect(try await database.searchHistory("notes", limit: 10).isEmpty)
    }

    @Test func historyIsKeptWhenTheDatabaseIsReopenedAndStaysInItsOwnProfileFile() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = StoreLayout(root: root)
        let work = ProfileID(rawValue: UUID())
        let personal = ProfileID(rawValue: UUID())

        do {
            let database = try ProfileDatabase(file: layout.profileDatabaseFile(for: work))
            try await database.recordVisit(to: url("https://intranet.example/wiki"))
            try await database.setTitle("Équipe wiki", ofLatestVisitTo: url("https://intranet.example/wiki"))
        }

        #expect(titles(try await ProfileDatabase(file: layout.profileDatabaseFile(for: work)).searchHistory("equipe", limit: 10))
            == ["Équipe wiki"])
        #expect(try await ProfileDatabase(file: layout.profileDatabaseFile(for: personal)).searchHistory("equipe", limit: 10).isEmpty)
    }
}

/// Clearing the history by time range.
@Suite struct ClearHistoryTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func database() async throws -> ProfileDatabase {
        let database = try ProfileDatabase.inMemory()
        // 30 minutes ago, 5 hours ago and 3 days ago.
        for (address, title, age) in [("https://recent.example/", "Recent news", 1_800.0),
                                      ("https://today.example/", "Today news", 18_000.0),
                                      ("https://old.example/", "Old news", 259_200.0)] {
            try await database.recordVisit(to: url(address), at: now.addingTimeInterval(-age))
            try await database.setTitle(title, ofLatestVisitTo: url(address))
        }
        return database
    }

    @Test func theLastHourRemovesOnlyTheVisitsOfTheLastHour() async throws {
        let database = try await database()

        try await database.clearHistory(since: ClearRange.lastHour.start(now: now))

        #expect(titles(try await database.searchHistory("news", limit: 10)) == ["Old news", "Today news"])
    }

    @Test func theLastDayKeepsWhatIsOlder() async throws {
        let database = try await database()

        try await database.clearHistory(since: ClearRange.lastDay.start(now: now))

        #expect(titles(try await database.searchHistory("news", limit: 10)) == ["Old news"])
    }

    @Test func allTimeRemovesEveryVisitAndTheSearchFindsNothing() async throws {
        let database = try await database()

        try await database.clearHistory(since: ClearRange.allTime.start(now: now))

        #expect(try await database.searchHistory("news", limit: 10).isEmpty)
        #expect(try await database.searchHistory("example", limit: 10).isEmpty)
    }

    @Test func aPageVisitedBeforeAndInsideTheRangeKeepsItsEarlierVisit() async throws {
        let database = try await database()
        try await database.recordVisit(to: url("https://old.example/"), at: now.addingTimeInterval(-60))
        try await database.setTitle("Old news again", ofLatestVisitTo: url("https://old.example/"))

        try await database.clearHistory(since: ClearRange.lastHour.start(now: now))

        #expect(titles(try await database.searchHistory("old", limit: 10)) == ["Old news"])
    }
}
