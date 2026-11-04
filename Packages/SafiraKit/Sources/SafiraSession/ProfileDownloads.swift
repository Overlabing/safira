// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore
import SafiraStore

/// A running transfer the download engine can stop.
@MainActor
public protocol DownloadTransfer: AnyObject {
    /// Stops the transfer. The data to continue it later, when the engine can provide it.
    func cancel() async -> Data?
}

/// What starts a transfer again when the user retries a download. It reports through the manager, under the same
/// download identifier.
@MainActor
public protocol DownloadEngine: AnyObject {
    /// Continues from `download.resumeData` when there is some, starts over from `download.sourceURL` otherwise.
    func restart(_ download: DownloadRecord)
    /// Deletes what a download that did not complete left on disk.
    func discardPartialFile(of download: DownloadRecord)
}

/// One Profile's downloads: the list its download manager shows, kept in the Profile's own database, so that another
/// Profile never sees them. Without a database (a Private window's downloads, later) nothing is written anywhere.
@MainActor
@Observable
public final class ProfileDownloads {
    /// Newest first.
    public private(set) var all: [DownloadRecord]
    @ObservationIgnored public weak var engine: (any DownloadEngine)?
    @ObservationIgnored private var transfers: [DownloadID: any DownloadTransfer] = [:]
    @ObservationIgnored private let database: ProfileDatabase?
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let onError: @MainActor (String, any Error) -> Void

    /// - Parameter database: where downloads are kept; nil keeps them for this run only.
    public init(database: ProfileDatabase? = nil, now: @escaping @MainActor () -> Date = { Date() },
                onError: @escaping @MainActor (String, any Error) -> Void = { _, _ in }) {
        self.database = database
        self.now = now
        self.onError = onError
        all = []
        do {
            all = try database?.downloads() ?? []
        } catch {
            onError("The downloads could not be read", error)
        }
        // A transfer still marked active belongs to a run that ended without finishing it.
        for index in all.indices where all[index].state == .active {
            all[index].state = .failed
            all[index].finishedAt = now()
            persist(all[index])
        }
    }

    public var hasActiveDownload: Bool {
        all.contains { $0.state == .active }
    }

    public func download(_ id: DownloadID) -> DownloadRecord? {
        all.first { $0.id == id }
    }

    // MARK: Reported by the engine

    /// Lists a download that has just started. The file name is the engine's first guess until `named` replaces it.
    @discardableResult
    public func begin(from url: URL, fileName: String) -> DownloadID {
        let record = DownloadRecord(sourceURL: url, fileName: fileName, startedAt: now())
        all.insert(record, at: 0)
        persist(record)
        return record.id
    }

    public func attach(_ transfer: any DownloadTransfer, to id: DownloadID) {
        guard download(id)?.state == .active else { return }
        transfers[id] = transfer
    }

    public func named(_ id: DownloadID, fileName: String) {
        update(id) { $0.fileName = fileName }
    }

    /// Progress is kept for this run only; the database learns the byte count when the transfer ends.
    public func progress(_ id: DownloadID, received: Int64, total: Int64?) {
        guard let index = all.firstIndex(where: { $0.id == id && $0.state == .active }) else { return }
        all[index].receivedBytes = received
        all[index].totalBytes = total
    }

    /// - Parameter size: the size of the saved file, which settles the byte count whatever progress was reported.
    public func complete(_ id: DownloadID, fileName: String, fileBookmark: Data?, size: Int64? = nil) {
        guard download(id)?.state == .active else { return }
        transfers[id] = nil
        update(id) { record in
            record.state = .completed
            record.fileName = fileName
            record.fileBookmark = fileBookmark
            record.resumeData = nil
            record.finishedAt = now()
            if let size {
                record.receivedBytes = size
                record.totalBytes = size
            } else if let total = record.totalBytes {
                record.receivedBytes = total
            }
        }
    }

    /// The transfer broke off; `resumeData` lets the user continue it where it stopped.
    public func fail(_ id: DownloadID, resumeData: Data?) {
        guard download(id)?.state == .active else { return }
        transfers[id] = nil
        update(id) { record in
            record.state = .failed
            record.resumeData = resumeData
            record.finishedAt = now()
        }
    }

    // MARK: Asked by the user

    /// Stops a running download. It is listed as cancelled at once; the data to continue it arrives when the engine
    /// has stopped the transfer.
    public func cancel(_ id: DownloadID) async {
        guard download(id)?.state == .active else { return }
        let transfer = transfers.removeValue(forKey: id)
        update(id) { record in
            record.state = .cancelled
            record.finishedAt = now()
        }
        guard let resumeData = await transfer?.cancel(), download(id)?.state == .cancelled else { return }
        update(id) { $0.resumeData = resumeData }
    }

    /// Starts a cancelled or failed download again, where it stopped when the engine kept the data for it. False when
    /// the download cannot be retried, or no engine is there to do it.
    @discardableResult
    public func retry(_ id: DownloadID) -> Bool {
        guard let engine, let record = download(id), record.canRetry else { return false }
        var restarted = record
        if record.resumeData == nil { restarted.receivedBytes = 0 }
        update(id) { stored in
            stored.state = .active
            stored.finishedAt = nil
            if stored.resumeData == nil { stored.receivedBytes = 0 }
            stored.resumeData = nil
        }
        engine.restart(restarted)
        return true
    }

    /// Takes a download that is not running off the list. The file it saved stays where it is.
    public func remove(_ id: DownloadID) {
        guard let record = download(id), record.state != .active else { return }
        removeRecords([id])
    }

    /// Takes everything that is not running off the list.
    public func removeFinished() {
        removeRecords(all.filter { $0.state != .active }.map(\.id))
    }

    /// Stops every running download, keeping what is needed to continue them, for the app to quit.
    public func cancelActive() async {
        for record in all where record.state == .active {
            await cancel(record.id)
        }
    }

    /// Stops every running download and deletes what the unfinished ones left on disk, for a Profile that goes away.
    public func cancelAll() async {
        await cancelActive()
        for record in all where record.state != .completed {
            engine?.discardPartialFile(of: record)
        }
    }

    // MARK: Private

    private func update(_ id: DownloadID, _ change: (inout DownloadRecord) -> Void) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        change(&all[index])
        persist(all[index])
    }

    private func removeRecords(_ ids: [DownloadID]) {
        guard !ids.isEmpty else { return }
        do {
            try database?.removeDownloads(ids)
        } catch {
            onError("The downloads could not be removed from the list", error)
            return
        }
        for record in all where ids.contains(record.id) && record.state != .completed {
            engine?.discardPartialFile(of: record)
        }
        all.removeAll { ids.contains($0.id) }
    }

    private func persist(_ record: DownloadRecord) {
        do {
            try database?.save(record)
        } catch {
            onError("The download could not be saved", error)
        }
    }
}
