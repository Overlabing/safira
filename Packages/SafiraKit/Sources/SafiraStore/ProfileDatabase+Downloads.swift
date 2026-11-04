// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import GRDB
import SafiraCore

extension ProfileDatabase {
    /// This Profile's downloads, newest first. A row this build cannot read (an unknown state, a broken address) is
    /// left out of the list.
    public func downloads() throws -> [DownloadRecord] {
        try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, source_url, file_name, file_bookmark, state, bytes, total_bytes, resume_data, started_at,
                       finished_at
                FROM download ORDER BY started_at DESC, rowid DESC
                """).compactMap { row in
                guard let id = UUID(uuidString: row["id"]), let source = URL(string: row["source_url"]),
                      let state = DownloadState(rawValue: row["state"]) else { return nil }
                return DownloadRecord(
                    id: DownloadID(rawValue: id), sourceURL: source, fileName: row["file_name"],
                    fileBookmark: row["file_bookmark"], state: state, receivedBytes: row["bytes"],
                    totalBytes: row["total_bytes"], resumeData: row["resume_data"],
                    startedAt: Date(timeIntervalSince1970: row["started_at"]),
                    finishedAt: (row["finished_at"] as Double?).map(Date.init(timeIntervalSince1970:)))
            }
        }
    }

    /// Adds the download or replaces the saved one with the same identifier.
    public func save(_ download: DownloadRecord) throws {
        try queue.write { db in
            try db.execute(sql: """
                INSERT OR REPLACE INTO download
                    (id, source_url, file_name, file_bookmark, state, bytes, total_bytes, resume_data, started_at,
                     finished_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [download.id.rawValue.uuidString, download.sourceURL.absoluteString, download.fileName,
                                 download.fileBookmark, download.state.rawValue, download.receivedBytes,
                                 download.totalBytes, download.resumeData, download.startedAt.timeIntervalSince1970,
                                 download.finishedAt?.timeIntervalSince1970])
        }
    }

    public func removeDownloads(_ ids: [DownloadID]) throws {
        try queue.write { db in
            try db.execute(sql: "DELETE FROM download WHERE id IN (\(databaseQuestionMarks(count: ids.count)))",
                           arguments: StatementArguments(ids.map(\.rawValue.uuidString)))
        }
    }
}
