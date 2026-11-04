// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
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
private let archive = URL(string: "https://files.example/archive.zip")!
private let report = URL(string: "https://files.example/report.pdf")!
private let start = Date(timeIntervalSince1970: 1_700_000_000)

/// Stands for WebKit: records what the manager asks of it and keeps the running transfers so a test can stop them.
@MainActor
private final class SimulatedEngine: DownloadEngine {
    var restarted: [DownloadRecord] = []
    var discarded: [DownloadRecord] = []

    func restart(_ download: DownloadRecord) { restarted.append(download) }
    func discardPartialFile(of download: DownloadRecord) { discarded.append(download) }
}

@MainActor
private final class SimulatedTransfer: DownloadTransfer {
    let resumeData: Data?
    private(set) var cancelCount = 0

    init(resumeData: Data? = nil) { self.resumeData = resumeData }

    func cancel() async -> Data? {
        cancelCount += 1
        return resumeData
    }
}

@MainActor
@Suite struct ProfileDownloadsTests {
    private func downloads(_ profile: ProfileID, in root: TemporaryRoot, engine: SimulatedEngine? = nil,
                           now: @escaping @MainActor () -> Date = { start }) throws -> ProfileDownloads {
        let downloads = ProfileDownloads(database: try ProfileDatabase(file: root.layout.profileDatabaseFile(for: profile)),
                                         now: now)
        downloads.engine = engine
        return downloads
    }

    @Test func aDownloadIsListedInTheProfileThatStartedItAndInNoOther() throws {
        let root = TemporaryRoot()
        let workDownloads = try downloads(work, in: root)
        let personalDownloads = try downloads(personal, in: root)

        let id = workDownloads.begin(from: archive, fileName: "archive.zip")

        #expect(workDownloads.all.map(\.id) == [id])
        #expect(workDownloads.all.first?.sourceURL == archive)
        #expect(workDownloads.all.first?.state == .active)
        #expect(personalDownloads.all == [])
        #expect(try downloads(personal, in: root).all == [])
        #expect(try downloads(work, in: root).all.map(\.id) == [id])
    }

    @Test func downloadsAreListedNewestFirstWithTheirProgressAndSize() throws {
        let downloads = ProfileDownloads()
        let first = downloads.begin(from: archive, fileName: "archive.zip")
        let second = downloads.begin(from: report, fileName: "report.pdf")

        downloads.progress(second, received: 250, total: 1000)
        downloads.named(second, fileName: "report 2.pdf")

        #expect(downloads.all.map(\.id) == [second, first])
        #expect(downloads.all[0].fileName == "report 2.pdf")
        #expect(downloads.all[0].receivedBytes == 250)
        #expect(downloads.all[0].totalBytes == 1000)
        #expect(downloads.all[0].fractionCompleted == 0.25)
        #expect(downloads.all[1].fractionCompleted == nil)
        #expect(downloads.hasActiveDownload)
    }

    @Test func aCompletedDownloadKeepsItsFileNameBookmarkAndSizeAfterAReopen() throws {
        let root = TemporaryRoot()
        var clock = start
        let first = try downloads(work, in: root, now: { clock })
        let id = first.begin(from: archive, fileName: "archive.zip")
        first.progress(id, received: 700, total: 1000)
        clock = start.addingTimeInterval(9)

        first.complete(id, fileName: "archive 2.zip", fileBookmark: Data([1, 2, 3]))

        let reopened = try downloads(work, in: root).all
        #expect(reopened == [
            DownloadRecord(id: id, sourceURL: archive, fileName: "archive 2.zip", fileBookmark: Data([1, 2, 3]),
                           state: .completed, receivedBytes: 1000, totalBytes: 1000, startedAt: start,
                           finishedAt: start.addingTimeInterval(9)),
        ])
        #expect(first.hasActiveDownload == false)
    }

    @Test func cancellingStopsTheTransferListsItCancelledAndKeepsTheDataToContinueIt() async throws {
        let root = TemporaryRoot()
        let downloads = try downloads(work, in: root)
        let id = downloads.begin(from: archive, fileName: "archive.zip")
        let transfer = SimulatedTransfer(resumeData: Data([9, 8, 7]))
        downloads.attach(transfer, to: id)
        downloads.progress(id, received: 300, total: 1000)

        await downloads.cancel(id)

        #expect(transfer.cancelCount == 1)
        let cancelled = try #require(downloads.download(id))
        #expect(cancelled.state == .cancelled)
        #expect(cancelled.resumeData == Data([9, 8, 7]))
        #expect(cancelled.receivedBytes == 300)
        #expect(cancelled.canRetry)
        #expect(try self.downloads(work, in: root).download(id)?.resumeData == Data([9, 8, 7]))
    }

    @Test func aTransferThatEndsAfterTheCancelDoesNotChangeTheCancelledDownload() async {
        let downloads = ProfileDownloads()
        let id = downloads.begin(from: archive, fileName: "archive.zip")
        downloads.attach(SimulatedTransfer(), to: id)

        await downloads.cancel(id)
        downloads.fail(id, resumeData: Data([1]))
        downloads.complete(id, fileName: "archive.zip", fileBookmark: nil)
        downloads.progress(id, received: 999, total: 1000)

        #expect(downloads.download(id)?.state == .cancelled)
        #expect(downloads.download(id)?.resumeData == nil)
        #expect(downloads.download(id)?.receivedBytes == 0)
    }

    @Test func retryingACancelledDownloadAsksTheEngineToContinueFromItsData() async throws {
        let engine = SimulatedEngine()
        let downloads = ProfileDownloads()
        downloads.engine = engine
        let id = downloads.begin(from: archive, fileName: "archive.zip")
        downloads.attach(SimulatedTransfer(resumeData: Data([5])), to: id)
        downloads.progress(id, received: 400, total: 1000)
        await downloads.cancel(id)

        #expect(downloads.retry(id))

        #expect(engine.restarted.map(\.id) == [id])
        #expect(engine.restarted.first?.resumeData == Data([5]))
        #expect(engine.restarted.first?.sourceURL == archive)
        let retried = try #require(downloads.download(id))
        #expect(retried.state == .active)
        #expect(retried.receivedBytes == 400)
        #expect(retried.resumeData == nil)
        #expect(retried.finishedAt == nil)
        #expect(downloads.all.count == 1)
    }

    @Test func retryingADownloadThatKeptNoDataStartsOverFromTheBeginning() throws {
        let engine = SimulatedEngine()
        let downloads = ProfileDownloads()
        downloads.engine = engine
        let id = downloads.begin(from: archive, fileName: "archive.zip")
        downloads.progress(id, received: 400, total: 1000)
        downloads.fail(id, resumeData: nil)

        #expect(downloads.retry(id))

        #expect(engine.restarted.first?.resumeData == nil)
        #expect(engine.restarted.first?.receivedBytes == 0)
        #expect(downloads.download(id)?.receivedBytes == 0)
    }

    @Test func onlyAStoppedDownloadCanBeRetriedAndOnlyWithAnEngine() throws {
        let engine = SimulatedEngine()
        let downloads = ProfileDownloads()
        let running = downloads.begin(from: archive, fileName: "archive.zip")
        let finished = downloads.begin(from: report, fileName: "report.pdf")
        downloads.complete(finished, fileName: "report.pdf", fileBookmark: nil)
        downloads.engine = engine

        #expect(downloads.retry(running) == false)
        #expect(downloads.retry(finished) == false)
        #expect(downloads.retry(DownloadID()) == false)
        #expect(engine.restarted == [])

        downloads.fail(running, resumeData: nil)
        downloads.engine = nil
        #expect(downloads.retry(running) == false)
        #expect(downloads.download(running)?.state == .failed)
    }

    @Test func aDownloadRunningWhenSafiraQuitIsListedFailedAtTheNextLaunch() throws {
        let root = TemporaryRoot()
        let first = try downloads(work, in: root)
        let running = first.begin(from: archive, fileName: "archive.zip")
        let finished = first.begin(from: report, fileName: "report.pdf")
        first.complete(finished, fileName: "report.pdf", fileBookmark: nil)

        let next = try downloads(work, in: root, now: { start.addingTimeInterval(3600) })

        #expect(next.download(running)?.state == .failed)
        #expect(next.download(running)?.finishedAt == start.addingTimeInterval(3600))
        #expect(next.download(finished)?.state == .completed)
        #expect(next.hasActiveDownload == false)
        #expect(try downloads(work, in: root).download(running)?.state == .failed)
    }

    @Test func removingADownloadKeepsTheFileAndDiscardsTheLeftoverOfAStoppedOne() async throws {
        let root = TemporaryRoot()
        let engine = SimulatedEngine()
        let downloads = try downloads(work, in: root, engine: engine)
        let running = downloads.begin(from: archive, fileName: "archive.zip")
        let finished = downloads.begin(from: report, fileName: "report.pdf")
        downloads.complete(finished, fileName: "report.pdf", fileBookmark: nil)
        let stopped = downloads.begin(from: URL(string: "https://files.example/c.iso")!, fileName: "c.iso")
        downloads.fail(stopped, resumeData: nil)

        downloads.remove(running)
        downloads.remove(finished)
        downloads.remove(stopped)

        #expect(downloads.all.map(\.id) == [running])
        #expect(engine.discarded.map(\.id) == [stopped])
        #expect(try self.downloads(work, in: root).all.map(\.id) == [running])
    }

    @Test func clearingTheListRemovesWhatIsNotRunning() throws {
        let root = TemporaryRoot()
        let downloads = try downloads(work, in: root)
        let running = downloads.begin(from: archive, fileName: "archive.zip")
        let finished = downloads.begin(from: report, fileName: "report.pdf")
        downloads.complete(finished, fileName: "report.pdf", fileBookmark: nil)

        downloads.removeFinished()

        #expect(downloads.all.map(\.id) == [running])
        #expect(try self.downloads(work, in: root).all.map(\.id) == [running])
    }

    @Test func downloadsWithoutADatabaseNeverReachAnyProfileDatabase() throws {
        let root = TemporaryRoot()
        let privateDownloads = ProfileDownloads()
        let id = privateDownloads.begin(from: archive, fileName: "archive.zip")
        privateDownloads.complete(id, fileName: "archive.zip", fileBookmark: nil)

        #expect(privateDownloads.all.count == 1)
        #expect(try downloads(work, in: root).all == [])
        #expect(ProfileDownloads().all == [])
    }

    @Test func stoppingEveryDownloadOfAProfileThatGoesAwayLeavesNothingRunningAndNoLeftover() async {
        let engine = SimulatedEngine()
        let downloads = ProfileDownloads()
        downloads.engine = engine
        let first = downloads.begin(from: archive, fileName: "archive.zip")
        let second = downloads.begin(from: report, fileName: "report.pdf")
        downloads.attach(SimulatedTransfer(), to: first)
        downloads.attach(SimulatedTransfer(), to: second)
        let third = downloads.begin(from: report, fileName: "done.pdf")
        downloads.complete(third, fileName: "done.pdf", fileBookmark: nil)

        await downloads.cancelAll()

        #expect(downloads.hasActiveDownload == false)
        #expect(Set(engine.discarded.map(\.id)) == [first, second])
    }

    @Test func stoppingForQuitKeepsTheDataAndLeavesTheFilesForALaterRetry() async throws {
        let root = TemporaryRoot()
        let engine = SimulatedEngine()
        let downloads = try downloads(work, in: root, engine: engine)
        let id = downloads.begin(from: archive, fileName: "archive.zip")
        downloads.attach(SimulatedTransfer(resumeData: Data([4, 2])), to: id)

        await downloads.cancelActive()

        #expect(engine.discarded == [])
        let reopened = try #require(try self.downloads(work, in: root).download(id))
        #expect(reopened.state == .cancelled)
        #expect(reopened.resumeData == Data([4, 2]))
    }
}
