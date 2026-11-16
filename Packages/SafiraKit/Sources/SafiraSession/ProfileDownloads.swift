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
    /// The downloads started, retried or resumed since launch: they keep the sidebar's button shown until cleared.
    private var startedThisRun: Set<DownloadID> = []
    /// The downloads that failed since the list was last opened.
    private var unseenFailures: Set<DownloadID> = []
    private var finishedCount = 0
    /// Why a download of this run failed, in the engine's words; kept for this run only.
    private var failureReasons: [DownloadID: String] = [:]
    /// The downloads a previous run left running: they stopped because Safira quit.
    @ObservationIgnored private var interruptedByQuit: Set<DownloadID> = []
    /// Where each running transfer was first measured in this run, for its time left.
    @ObservationIgnored private var rates: [DownloadID: TransferRate] = [:]

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
            interruptedByQuit.insert(all[index].id)
            persist(all[index])
        }
    }

    /// True while files are saved in Safira's own folder because the user declined access to the Downloads folder.
    public private(set) var savesInAppFolder = false

    public func setSavesInAppFolder(_ value: Bool) {
        if savesInAppFolder != value { savesInAppFolder = value }
    }

    public var hasActiveDownload: Bool {
        all.contains { $0.state == .active }
    }

    /// What the sidebar's downloads button shows.
    public var indicator: DownloadsIndicator {
        DownloadsIndicator(downloads: all, startedThisRun: startedThisRun, unseenFailures: unseenFailures,
                           finishedCount: finishedCount)
    }

    /// Why a download failed, when it is known.
    public func failure(_ id: DownloadID) -> DownloadFailure? {
        guard download(id)?.state == .failed else { return nil }
        if let reason = failureReasons[id] { return .error(reason) }
        return interruptedByQuit.contains(id) ? .quit : .unknown
    }

    /// The list was opened: the failures it shows no longer call for attention.
    public func markFailuresSeen() {
        if !unseenFailures.isEmpty { unseenFailures = [] }
    }

    /// The time a running download has left at its current rate, nil while it cannot be told.
    public func timeRemaining(_ id: DownloadID) -> TimeInterval? {
        guard let record = download(id), record.state == .active, let rate = rates[id] else { return nil }
        return rate.timeRemaining(received: record.receivedBytes, total: record.totalBytes, at: now())
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
        startedThisRun.insert(record.id)
        persist(record)
        return record.id
    }

    public func attach(_ transfer: any DownloadTransfer, to id: DownloadID) {
        guard download(id)?.state == .active else { return }
        transfers[id] = transfer
    }

    /// The engine has chosen where and under which name the file is saved.
    public func named(_ id: DownloadID, fileName: String, folder: URL? = nil) {
        update(id) {
            $0.fileName = fileName
            if let folder { $0.folder = folder }
        }
    }

    /// Progress is kept for this run only; the database learns the byte count when the transfer ends.
    public func progress(_ id: DownloadID, received: Int64, total: Int64?) {
        guard let index = all.firstIndex(where: { $0.id == id && $0.state == .active }) else { return }
        if rates[id] == nil { rates[id] = TransferRate(startBytes: received, startTime: now()) }
        all[index].receivedBytes = received
        all[index].totalBytes = total
    }

    /// - Parameter size: the size of the saved file, which settles the byte count whatever progress was reported.
    public func complete(_ id: DownloadID, fileName: String, fileBookmark: Data?, size: Int64? = nil) {
        guard download(id)?.state == .active else { return }
        transfers[id] = nil
        rates[id] = nil
        finishedCount += 1
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
    /// - Parameter reason: the engine's description of the error, shown in the list.
    public func fail(_ id: DownloadID, resumeData: Data?, reason: String? = nil) {
        guard download(id)?.state == .active else { return }
        failureReasons[id] = reason
        transfers[id] = nil
        rates[id] = nil
        unseenFailures.insert(id)
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
        if download(id)?.state == .paused {
            update(id) { $0.state = .cancelled }
            return
        }
        await stop(id, as: .cancelled)
    }

    /// Stops a running download to continue it later with `resume`. Unlike a cancelled one it stays in the list on
    /// Clear, and keeps the sidebar's button shown.
    public func pause(_ id: DownloadID) async {
        await stop(id, as: .paused)
    }

    /// Starts a cancelled or failed download again, where it stopped when the engine kept the data for it. False when
    /// the download cannot be retried, or no engine is there to do it.
    @discardableResult
    public func retry(_ id: DownloadID) -> Bool {
        guard let record = download(id), record.canRetry else { return false }
        return restart(record)
    }

    /// Continues a paused download. False when it is not paused, or no engine is there to do it.
    @discardableResult
    public func resume(_ id: DownloadID) -> Bool {
        guard let record = download(id), record.canResume else { return false }
        return restart(record)
    }

    private func restart(_ record: DownloadRecord) -> Bool {
        guard let engine else { return false }
        let id = record.id
        startedThisRun.insert(id)
        unseenFailures.remove(id)
        failureReasons[id] = nil
        interruptedByQuit.remove(id)
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

    /// Clear: takes the finished, failed and cancelled downloads off the list; the running and paused ones stay. The
    /// files saved stay where they are.
    public func removeFinished() {
        removeRecords(all.filter { $0.state != .active && $0.state != .paused }.map(\.id))
    }

    /// Whether Clear would take anything off the list.
    public var canClear: Bool {
        all.contains { $0.state != .active && $0.state != .paused }
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

    private func stop(_ id: DownloadID, as state: DownloadState) async {
        guard download(id)?.state == .active else { return }
        let transfer = transfers.removeValue(forKey: id)
        rates[id] = nil
        update(id) { record in
            record.state = state
            record.finishedAt = now()
        }
        guard let resumeData = await transfer?.cancel(), download(id)?.state == state else { return }
        update(id) { $0.resumeData = resumeData }
    }

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
        startedThisRun.subtract(ids)
        unseenFailures.subtract(ids)
    }

    private func persist(_ record: DownloadRecord) {
        do {
            try database?.save(record)
        } catch {
            onError("The download could not be saved", error)
        }
    }
}

/// Why a download failed.
public enum DownloadFailure: Hashable, Sendable {
    /// The engine reported this error.
    case error(String)
    /// It was running when Safira quit.
    case quit
    case unknown
}

