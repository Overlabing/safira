// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import Testing

private let start = Date(timeIntervalSince1970: 1_700_000_000)
private let movie = URL(string: "https://files.example/movie.mov")!
private let archive = URL(string: "https://files.example/archive.zip")!
private let notes = URL(string: "https://files.example/notes.txt")!

@MainActor
private final class Clock {
    var now = start
}

@MainActor
private final class Engine: DownloadEngine {
    var restarted: [DownloadRecord] = []
    func restart(_ download: DownloadRecord) { restarted.append(download) }
    func discardPartialFile(of download: DownloadRecord) {}
}

@MainActor
private final class Transfer: DownloadTransfer {
    func cancel() async -> Data? { Data("resume".utf8) }
}

/// The sidebar button's state and the panel's actions, through `ProfileDownloads`.
@MainActor
@Suite struct DownloadsIndicatorTests {
    @Test func theButtonIsHiddenUntilADownloadStarts() {
        let downloads = ProfileDownloads()
        #expect(downloads.indicator == .hidden)
        downloads.begin(from: movie, fileName: "movie.mov")
        #expect(downloads.indicator == DownloadsIndicator(isVisible: true, runningCount: 1))
    }

    @Test func theProgressCombinesTheRunningDownloadsWhoseSizeIsKnown() {
        let downloads = ProfileDownloads()
        let first = downloads.begin(from: movie, fileName: "movie.mov")
        let second = downloads.begin(from: archive, fileName: "archive.zip")
        let third = downloads.begin(from: notes, fileName: "notes.txt")
        downloads.progress(first, received: 300, total: 1_000)
        downloads.progress(second, received: 600, total: 1_000)
        downloads.progress(third, received: 5_000, total: nil)
        #expect(downloads.indicator.runningCount == 3)
        #expect(downloads.indicator.fraction == 0.45)
        #expect(downloads.indicator.percent == 45)
    }

    @Test func noSizeKnownGivesNoFraction() {
        let downloads = ProfileDownloads()
        let id = downloads.begin(from: movie, fileName: "movie.mov")
        downloads.progress(id, received: 5_000, total: nil)
        #expect(downloads.indicator.fraction == nil)
    }

    @Test func aFinishedDownloadCountsForTheBounceAndKeepsTheButtonShown() {
        let downloads = ProfileDownloads()
        let id = downloads.begin(from: movie, fileName: "movie.mov")
        downloads.complete(id, fileName: "movie.mov", fileBookmark: nil, size: 10)
        #expect(downloads.indicator == DownloadsIndicator(isVisible: true, finishedCount: 1))
    }

    @Test func aFailureCallsForAttentionUntilTheListIsOpened() {
        let downloads = ProfileDownloads()
        let id = downloads.begin(from: movie, fileName: "movie.mov")
        downloads.fail(id, resumeData: nil, reason: "The network connection was lost.")
        #expect(downloads.indicator.needsAttention)
        #expect(downloads.failure(id) == .error("The network connection was lost."))
        downloads.markFailuresSeen()
        #expect(!downloads.indicator.needsAttention)
        #expect(downloads.indicator.isVisible)
    }

    @Test func pauseThenResumeContinuesFromTheEnginesData() async {
        let downloads = ProfileDownloads()
        let engine = Engine()
        downloads.engine = engine
        let id = downloads.begin(from: movie, fileName: "movie.mov")
        downloads.attach(Transfer(), to: id)
        downloads.progress(id, received: 400, total: 1_000)
        await downloads.pause(id)
        #expect(downloads.download(id)?.state == .paused)
        #expect(downloads.download(id)?.resumeData == Data("resume".utf8))
        #expect(downloads.indicator == DownloadsIndicator(isVisible: true))
        #expect(downloads.retry(id) == false)
        #expect(downloads.resume(id))
        #expect(downloads.download(id)?.state == .active)
        #expect(engine.restarted.map(\.resumeData) == [Data("resume".utf8)])
        #expect(engine.restarted.map(\.receivedBytes) == [400])
    }

    @Test func cancellingAPausedDownloadCancelsIt() async {
        let downloads = ProfileDownloads()
        let id = downloads.begin(from: movie, fileName: "movie.mov")
        await downloads.pause(id)
        await downloads.cancel(id)
        #expect(downloads.download(id)?.state == .cancelled)
    }

    @Test func retryRestartsAFailedDownloadAndClearsItsFailure() {
        let downloads = ProfileDownloads()
        let engine = Engine()
        downloads.engine = engine
        let id = downloads.begin(from: movie, fileName: "movie.mov")
        downloads.progress(id, received: 400, total: 1_000)
        downloads.fail(id, resumeData: nil, reason: "Lost")
        #expect(downloads.retry(id))
        #expect(downloads.download(id)?.state == .active)
        #expect(downloads.download(id)?.receivedBytes == 0)
        #expect(downloads.failure(id) == nil)
        #expect(!downloads.indicator.needsAttention)
        #expect(engine.restarted.map(\.sourceURL) == [movie])
    }

    @Test func clearKeepsRunningAndPausedDownloadsAndHidesTheButtonWhenNothingIsLeft() async {
        let downloads = ProfileDownloads()
        let done = downloads.begin(from: movie, fileName: "movie.mov")
        downloads.complete(done, fileName: "movie.mov", fileBookmark: nil)
        let failed = downloads.begin(from: notes, fileName: "notes.txt")
        downloads.fail(failed, resumeData: nil)
        let paused = downloads.begin(from: archive, fileName: "archive.zip")
        await downloads.pause(paused)
        #expect(downloads.canClear)
        downloads.removeFinished()
        #expect(downloads.all.map(\.id) == [paused])
        #expect(!downloads.canClear)
        #expect(downloads.indicator.isVisible)
        await downloads.cancel(paused)
        downloads.removeFinished()
        #expect(downloads.all.isEmpty)
        #expect(downloads.indicator == DownloadsIndicator(isVisible: false, finishedCount: 1))
    }

    @Test func downloadsOfAnEarlierRunDoNotShowTheButton() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = StoreLayout(root: root).profileDatabaseFile(for: ProfileID(rawValue: UUID()))
        do {
            let downloads = ProfileDownloads(database: try ProfileDatabase(file: file))
            let id = downloads.begin(from: movie, fileName: "movie.mov")
            downloads.complete(id, fileName: "movie.mov", fileBookmark: nil)
            downloads.begin(from: archive, fileName: "archive.zip")
        }
        let relaunched = ProfileDownloads(database: try ProfileDatabase(file: file))
        #expect(relaunched.all.count == 2)
        #expect(relaunched.indicator == .hidden)
        let interrupted = try #require(relaunched.all.first { $0.fileName == "archive.zip" })
        #expect(relaunched.failure(interrupted.id) == .quit)
    }

    @Test func eachProfileHasItsOwnButtonState() {
        let work = ProfileDownloads()
        let personal = ProfileDownloads()
        let id = work.begin(from: movie, fileName: "movie.mov")
        work.fail(id, resumeData: nil)
        #expect(work.indicator.needsAttention)
        #expect(personal.indicator == .hidden)
    }

    @Test func timeLeftFollowsTheRateMeasuredInThisRun() {
        let clock = Clock()
        let downloads = ProfileDownloads(now: { clock.now })
        let id = downloads.begin(from: movie, fileName: "movie.mov")
        downloads.progress(id, received: 0, total: 1_000)
        #expect(downloads.timeRemaining(id) == nil)
        clock.now = start.addingTimeInterval(10)
        downloads.progress(id, received: 250, total: 1_000)
        #expect(downloads.timeRemaining(id) == 30)
    }
}
