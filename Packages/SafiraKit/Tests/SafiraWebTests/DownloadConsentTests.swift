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

/// Holds the stand-in for macOS's consent prompt open until the test answers it.
@MainActor
private final class Prompt {
    private var waiters: [CheckedContinuation<Bool, Never>] = []
    private(set) var asked = 0

    func ask() async -> Bool {
        asked += 1
        return await withCheckedContinuation { waiters.append($0) }
    }

    func answer(_ allowed: Bool) {
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume(returning: allowed) }
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
            context.web.downloadsAccess = { _ in await prompt.ask() }

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
            context.web.downloadsAccess = { _ in await prompt.ask() }

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
            context.web.downloadsAccess = { _ in await prompt.ask() }

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
            var allowed = false
            context.web.downloadsAccess = { _ in allowed }

            _ = try await clickDownloadLink(in: context, server: server)
            try await waitUntil("the download is saved") { isFinished(context) }

            let saved = try #require(context.downloads.all.first)
            #expect(saved.state == .completed)
            #expect(saved.savedFileURL()?.resolvingSymlinksInPath()
                == folders.appFolder.appending(path: "small.bin").resolvingSymlinksInPath())
            #expect(folders.files(in: folders.appFolder) == ["small.bin"])
            #expect(folders.files(in: folders.downloads) == [])
            #expect(context.downloads.savesInAppFolder)

            allowed = true
            context.session.closeAllTabs()
            _ = try await clickDownloadLink(in: context, server: server)
            try await waitUntil("the second download is saved") { context.downloads.all.count == 2 && isFinished(context) }

            #expect(folders.files(in: folders.downloads) == ["small.bin"])
            #expect(context.downloads.savesInAppFolder == false)
        }
    }

    @Test func askingAtTheMomentTheUserChoseSettlesTheFolderBeforeAnyDownload() async throws {
        let folders = Folders()
        try await run(folders) { context in
            let prompt = Prompt()
            context.web.downloadsAccess = { _ in await prompt.ask() }

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
}
