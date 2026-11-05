// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import SafiraWeb
import Testing
import WebKit

@testable import SafiraWeb

/// A folder pair for one test, standing in for the Downloads folder and the app's own: the tests never touch the real
/// Downloads folder, whose first use makes macOS ask the user.
private final class Folders {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "safira-consent-\(UUID().uuidString)", directoryHint: .isDirectory)
    var layout: StoreLayout { StoreLayout(root: root) }
    var downloads: URL { root.appending(path: "Downloads", directoryHint: .isDirectory) }
    var appFolder: URL { root.appending(path: "Container", directoryHint: .isDirectory) }

    deinit { try? FileManager.default.removeItem(at: root) }

    func files(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted()
    }
}

/// A value a background thread and the test both touch.
private final class Shared<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value

    init(_ value: Value) { stored = value }

    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func update(_ change: (inout Value) -> Void) { lock.withLock { change(&stored) } }
}

/// The stand-in for macOS's consent prompt: it parks the calling background thread on a semaphore, as the real prompt
/// parks the thread that opened the folder, until the test answers.
private final class Prompt: @unchecked Sendable {
    private let state = Shared((asked: 0, waiting: 0, answer: false, onMainThread: [Bool]()))
    private let semaphore = DispatchSemaphore(value: 0)

    var asked: Int { state.value.asked }
    var askedOnTheMainThread: Bool { state.value.onMainThread.contains(true) }

    /// Blocks the thread it is called on. A plain function, not an `async` one: blocking is the point.
    func ask() -> Bool {
        state.update {
            $0.asked += 1
            $0.waiting += 1
            $0.onMainThread.append(Thread.isMainThread)
        }
        semaphore.wait()
        return state.value.answer
    }

    func answer(_ allowed: Bool) {
        let waiting = state.value.waiting
        state.update {
            $0.answer = allowed
            $0.waiting = 0
        }
        for _ in 0..<waiting { semaphore.signal() }
    }
}

@MainActor
@Suite(.serialized) struct DownloadConsentTests {
    private func run(_ folders: Folders, _ body: (ProfileContext) async throws -> Void) async throws {
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: folders.layout)
            defer { ids = registry.profiles.map(\.id) }
            registry.active.web.downloadsDirectory = folders.downloads
            registry.active.web.downloadsFallbackDirectory = folders.appFolder
            registry.active.web.downloadController.container = folders.root
            try await body(registry.active)
            await registry.active.web.cancelDownloads()
            registry.active.session.closeAllTabs()
        }
        for id in ids { await removeDataStoreWhenReleased(id) }
    }

    private func clickDownloadLink(in context: ProfileContext, server: DownloadServer) async throws -> WKWebView {
        context.session.submitCommandBar(server.url("/page.html").absoluteString)
        let tab = try #require(context.session.selectedTabID)
        let webView = try #require(context.web.webView(for: tab))
        try await waitUntil("the page loads") { webView.url == server.url("/page.html") && !webView.isLoading }
        _ = try await webView.evaluateJavaScript("document.getElementById('link').click()")
        return webView
    }

    private func isFinished(_ context: ProfileContext) -> Bool {
        !context.downloads.all.isEmpty && !context.downloads.hasActiveDownload
    }

    // MARK: The probe

    @Test func aFolderIsAllowedWhenItOpensOrDoesNotExistAndRefusedWhenMacOSForbidsIt() async throws {
        let folders = Folders()
        let readable = folders.root.appending(path: "readable", directoryHint: .isDirectory)
        let forbidden = folders.root.appending(path: "forbidden", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: readable, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: forbidden, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: forbidden.path(percentEncoded: false))
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: forbidden.path(percentEncoded: false)) }

        #expect(await FolderAccess.isAllowed(readable))
        #expect(await FolderAccess.isAllowed(folders.root.appending(path: "missing", directoryHint: .isDirectory)))
        #expect(await FolderAccess.isAllowed(forbidden) == false)
    }

    // MARK: A pending prompt

    @Test func aPromptLeftOpenKeepsThePageAndTheMainThreadRunningAndTheDownloadFollowsTheAnswer() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let folders = Folders()
        try await run(folders) { context in
            let prompt = Prompt()
            context.web.downloadsAccess = { _ in prompt.ask() }

            let webView = try await clickDownloadLink(in: context, server: server)
            try await waitUntil("the prompt is open") { prompt.asked == 1 }

            var ticks = 0
            let ticker = Task { @MainActor in
                while !Task.isCancelled {
                    ticks += 1
                    try? await Task.sleep(for: .milliseconds(10))
                }
            }
            #expect(try await webView.evaluateJavaScript("1 + 1") as? Int == 2)
            try await waitUntil("the main thread keeps running while the prompt is open") { ticks >= 5 }
            ticker.cancel()
            #expect(prompt.askedOnTheMainThread == false)

            #expect(context.downloads.all.map(\.state) == [.active])
            #expect(folders.files(in: folders.downloads) == [])
            #expect(folders.files(in: folders.appFolder) == [])

            prompt.answer(true)
            try await waitUntil("the download is saved") { isFinished(context) }

            #expect(context.downloads.all.map(\.state) == [.completed])
            #expect(folders.files(in: folders.downloads) == ["small.bin"])
            #expect(folders.files(in: folders.appFolder) == [])
            #expect(context.downloads.savesInAppFolder == false)
        }
    }

    @Test func twoDownloadsStartedWhileThePromptIsOpenShareOneQuestion() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let folders = Folders()
        try await run(folders) { context in
            let prompt = Prompt()
            context.web.downloadsAccess = { _ in prompt.ask() }

            let webView = try await clickDownloadLink(in: context, server: server)
            try await waitUntil("the first download is listed") { context.downloads.all.count == 1 && prompt.asked == 1 }
            _ = try await webView.evaluateJavaScript("document.getElementById('link').click()")
            try await waitUntil("the second download is listed") { context.downloads.all.count == 2 }
            try await Task.sleep(for: .milliseconds(300))
            #expect(prompt.asked == 1)

            prompt.answer(true)
            try await waitUntil("both downloads are saved") { context.downloads.all.count == 2 && isFinished(context) }
            #expect(folders.files(in: folders.downloads) == ["small 2.bin", "small.bin"])
        }
    }

    @Test func aDownloadCancelledWhileThePromptIsOpenSavesNothingWhenItIsAnswered() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let folders = Folders()
        try await run(folders) { context in
            let prompt = Prompt()
            context.web.downloadsAccess = { _ in prompt.ask() }

            _ = try await clickDownloadLink(in: context, server: server)
            try await waitUntil("the prompt is open") { prompt.asked == 1 }
            let id = try #require(context.downloads.all.first?.id)
            await context.downloads.cancel(id)

            prompt.answer(true)
            try await Task.sleep(for: .milliseconds(500))
            #expect(context.downloads.all.map(\.state) == [.cancelled])
            #expect(folders.files(in: folders.downloads) == [])
            #expect(folders.files(in: folders.appFolder) == [])
        }
    }

    // MARK: "Don't Allow"

    @Test func declinedAccessSavesInTheAppsOwnFolderAndSaysSoAndAllowingItLaterGoesBackToDownloads() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let folders = Folders()
        try await run(folders) { context in
            let allowed = Shared(false)
            context.web.downloadsAccess = { _ in allowed.value }

            _ = try await clickDownloadLink(in: context, server: server)
            try await waitUntil("the download is saved") { isFinished(context) }

            let saved = try #require(context.downloads.all.first)
            #expect(saved.state == .completed)
            #expect(saved.savedFileURL()?.resolvingSymlinksInPath()
                == folders.appFolder.appending(path: "small.bin").resolvingSymlinksInPath())
            #expect(folders.files(in: folders.appFolder) == ["small.bin"])
            #expect(folders.files(in: folders.downloads) == [])
            #expect(context.downloads.savesInAppFolder)
            #expect(saved.folder?.resolvingSymlinksInPath() == folders.appFolder.resolvingSymlinksInPath())

            allowed.value = true
            context.session.closeAllTabs()
            _ = try await clickDownloadLink(in: context, server: server)
            try await waitUntil("the second download is saved") { context.downloads.all.count == 2 && isFinished(context) }

            #expect(folders.files(in: folders.downloads) == ["small.bin"])
            #expect(context.downloads.savesInAppFolder == false)
            #expect(context.downloads.all.first?.folder?.resolvingSymlinksInPath() == folders.downloads.resolvingSymlinksInPath())
        }
    }

    @Test func askingAtTheMomentTheUserChoseSettlesTheFolderBeforeAnyDownload() async throws {
        let folders = Folders()
        try await run(folders) { context in
            let prompt = Prompt()
            context.web.downloadsAccess = { _ in prompt.ask() }

            let asking = Task { await context.web.prepareDownloadsAccess() }
            try await waitUntil("the prompt is open") { prompt.asked == 1 }
            #expect(context.downloads.savesInAppFolder == false)
            prompt.answer(false)
            await asking.value

            #expect(context.downloads.savesInAppFolder)
            #expect(context.downloads.all == [])
            #expect(folders.files(in: folders.downloads) == [])
            #expect(folders.files(in: folders.appFolder) == [])
        }
    }

    // MARK: The fallback folder

    @Test func theDefaultFallbackIsARealFolderOfTheContainerAndNotTheSymbolicEntryToTheDeclinedDownloads() throws {
        let declined = DownloadController.userDownloadsDirectory().resolvingSymlinksInPath()
        let fallback = FallbackFolder.defaultFolder()

        #expect(fallback.resolvingSymlinksInPath().path != declined.path)
        #expect(!fallback.resolvingSymlinksInPath().path.hasPrefix(declined.path + "/"))
        #expect(fallback.pathComponents.suffix(2) == ["Safira", "Downloads"])
        #expect(fallback.pathComponents.contains("Application Support"))
        let isSymlink = try? fallback.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink
        #expect(isSymlink != true)
    }

    @Test func aFallbackThatLeadsToTheDeclinedFolderOrLeavesTheContainerIsRefused() throws {
        let folders = Folders()
        let manager = FileManager.default
        // A container as macOS builds it: its Downloads entry is a link to the user's real Downloads folder.
        let data = folders.root.appending(path: "Container/Data", directoryHint: .isDirectory)
        let support = data.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        try manager.createDirectory(at: folders.downloads, withIntermediateDirectories: true)
        try manager.createDirectory(at: support, withIntermediateDirectories: true)
        let entry = data.appending(path: "Downloads")
        try manager.createSymbolicLink(at: entry, withDestinationURL: folders.downloads)
        let outside = folders.root.appending(path: "Elsewhere", directoryHint: .isDirectory)
        let inside = support.appending(path: "Safira/Downloads", directoryHint: .isDirectory)

        #expect(FallbackFolder.prepare(entry, declined: folders.downloads, container: data) == nil)
        #expect(FallbackFolder.prepare(entry.appending(path: "sub"), declined: folders.downloads, container: data) == nil)
        #expect(FallbackFolder.prepare(outside, declined: folders.downloads, container: data) == nil)
        let link = support.appending(path: "Linked")
        try manager.createSymbolicLink(at: link, withDestinationURL: support)
        #expect(FallbackFolder.prepare(link, declined: folders.downloads, container: data) == nil)
        let prepared = FallbackFolder.prepare(inside, declined: folders.downloads, container: data)
        #expect(prepared == inside.resolvingSymlinksInPath())
        var isDirectory: ObjCBool = false
        #expect(manager.fileExists(atPath: inside.path(percentEncoded: false), isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    @Test func aDeclinedDownloadWhoseFallbackCannotBeUsedSavesNothingInTheDeclinedFolder() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let folders = Folders()
        try await run(folders) { context in
            context.web.downloadsAccess = { _ in false }
            context.web.downloadsFallbackDirectory = folders.downloads.appending(path: "inside")

            _ = try await clickDownloadLink(in: context, server: server)
            try await Task.sleep(for: .seconds(1))

            #expect(folders.files(in: folders.downloads) == [])
            #expect(context.downloads.all.allSatisfy { $0.state != .completed })
        }
    }

    // MARK: The folder belongs to the download

    @Test func aDownloadRemembersItsFolderInTheProfileDatabase() throws {
        let folders = Folders()
        try FileManager.default.createDirectory(at: folders.root, withIntermediateDirectories: true)
        let database = try ProfileDatabase(file: folders.root.appending(path: "profile.sqlite"))
        let kept = DownloadRecord(sourceURL: URL(string: "https://example.com/a.bin")!, fileName: "a.bin",
                                  folder: folders.appFolder, startedAt: Date(timeIntervalSince1970: 10))
        let old = DownloadRecord(sourceURL: URL(string: "https://example.com/b.bin")!, fileName: "b.bin",
                                 startedAt: Date(timeIntervalSince1970: 5))
        try database.save(kept)
        try database.save(old)

        let read = try database.downloads()
        #expect(read.map(\.fileName) == ["a.bin", "b.bin"])
        #expect(read[0].folder == folders.appFolder)
        #expect(read[1].folder == nil)
    }

    @Test func aRetryAndAResumeLookInTheFolderOfTheDownloadNotTheProfilesCurrentOne() async throws {
        let folders = Folders()
        try await run(folders) { context in
            let controller = context.web.downloadController!
            let recorded = DownloadRecord(sourceURL: URL(string: "https://example.com/a.bin")!, fileName: "a.bin",
                                          folder: folders.appFolder, startedAt: Date())
            let predating = DownloadRecord(sourceURL: URL(string: "https://example.com/a.bin")!, fileName: "a.bin",
                                           startedAt: Date())

            #expect(controller.folder(for: recorded) == folders.appFolder)
            #expect(controller.folder(for: predating) == folders.downloads)
        }
    }

    @Test func aTransferStartedOverClearsItsOwnFoldersPartialFileAndNeverTheOneAnotherRunningDownloadWritesTo() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let folders = Folders()
        try await run(folders) { context in
            context.web.downloadsAccess = { _ in true }
            let controller = context.web.downloadController!
            server.hold(after: 10_000)
            context.session.submitCommandBar(server.url("/slow.bin").absoluteString)
            try await waitUntil("some bytes arrive") { (context.downloads.all.first?.receivedBytes ?? 0) >= 10_000 }
            #expect(folders.files(in: folders.downloads) == ["slow.bin.part"])

            let elsewhere = folders.root.appending(path: "Elsewhere", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
            try Data("old".utf8).write(to: elsewhere.appending(path: "slow.bin.part"))
            let ofAnotherFolder = DownloadRecord(sourceURL: server.url("/slow.bin"), fileName: "slow.bin",
                                                 state: .failed, folder: elsewhere, startedAt: Date())
            let ofTheSameFolder = DownloadRecord(sourceURL: server.url("/slow.bin"), fileName: "slow.bin",
                                                 state: .failed, startedAt: Date())

            controller.discardPartialFile(of: ofTheSameFolder)
            #expect(folders.files(in: folders.downloads) == ["slow.bin.part"])
            controller.discardPartialFile(of: ofAnotherFolder)
            #expect(folders.files(in: elsewhere) == [])
            #expect(folders.files(in: folders.downloads) == ["slow.bin.part"])

            server.release()
            try await waitUntil("the download is saved", timeout: .seconds(20)) { isFinished(context) }
            #expect(folders.files(in: folders.downloads) == ["slow.bin"])
        }
    }

    @Test func retryingADownloadSavedInTheFallbackFolderClearsThatFoldersPartialFileEvenOnceAccessIsAllowed() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let folders = Folders()
        try await run(folders) { context in
            let allowed = Shared(false)
            context.web.downloadsAccess = { _ in allowed.value }

            context.session.submitCommandBar(server.url("/broken.bin").absoluteString)
            try await waitUntil("the download fails") { context.downloads.all.first?.state == .failed }
            let id = try #require(context.downloads.all.first?.id)
            #expect(folders.files(in: folders.appFolder) == ["broken.bin.part"])

            allowed.value = true
            #expect(context.downloads.retry(id))
            try await waitUntil("the second transfer is made") { server.requestCount("/broken.bin") == 2 }
            try await waitUntil("the second transfer fails too") { context.downloads.all.first?.state == .failed }

            #expect(folders.files(in: folders.appFolder) == [])
            #expect(folders.files(in: folders.downloads) == ["broken.bin.part"])
            #expect(context.downloads.all.first?.folder?.resolvingSymlinksInPath() == folders.downloads.resolvingSymlinksInPath())
        }
    }

    // MARK: The probe

    @Test func theFolderProbeRunsOffTheMainThread() async throws {
        let folders = Folders()
        let threads = Shared([Bool]())

        let allowed = await FolderAccess.isAllowed(folders.root) { _ in
            threads.update { $0.append(Thread.isMainThread) }
            return true
        }

        #expect(allowed)
        #expect(threads.value == [false])
    }
}
