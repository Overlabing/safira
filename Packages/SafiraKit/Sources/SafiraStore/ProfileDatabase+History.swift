// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import GRDB
import SafiraCore

/// The Profile's history. It lives in the Profile's own database, so no search can reach another Profile's pages.
extension ProfileDatabase {
    /// Records that the Profile visited `url`. Only web addresses are history; anything else is ignored.
    public func recordVisit(to url: URL, at date: Date = Date()) async throws {
        guard let host = Self.historyHost(of: url) else { return }
        try await queue.write { db in
            try db.execute(sql: "INSERT INTO history_visit (url, host, visited_at) VALUES (?, ?, ?)",
                           arguments: [url.absoluteString, host, date.timeIntervalSince1970])
        }
    }

    /// Gives the latest visit to `url` its title.
    public func setTitle(_ title: String, ofLatestVisitTo url: URL) async throws {
        try await queue.write { db in
            try db.execute(sql: """
                UPDATE history_visit SET title = ?
                WHERE id = (SELECT MAX(id) FROM history_visit WHERE url = ?)
                """, arguments: [title, url.absoluteString])
        }
    }

    /// The pages whose title or address start a word with each word of `text`, most recently visited first, one
    /// entry per address. Letter case and accents are ignored: "cafe" finds "Café".
    public func searchHistory(_ text: String, limit: Int) async throws -> [HistoryEntry] {
        guard limit > 0, let pattern = FTS5Pattern(matchingAllPrefixesIn: text) else { return [] }
        return try await queue.read { db in
            // The bare title column takes its value from the row holding MAX(id), the address's latest visit.
            try Row.fetchAll(db, sql: """
                SELECT history_visit.url AS url, history_visit.title AS title, MAX(history_visit.id) AS latest
                FROM history_visit
                JOIN history_visit_search ON history_visit_search.rowid = history_visit.id
                WHERE history_visit_search MATCH ?
                GROUP BY history_visit.url
                ORDER BY latest DESC
                LIMIT ?
                """, arguments: [pattern, limit]).compactMap { row -> HistoryEntry? in
                guard let url = URL(string: row["url"] as String) else { return nil }
                return HistoryEntry(url: url, title: row["title"])
            }
        }
    }

    private static func historyHost(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        return host.lowercased()
    }
}
