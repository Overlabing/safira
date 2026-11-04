// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import SafiraWeb
import Testing
import WebKit

/// A fresh Application Support folder and downloads folder for one test, removed when the test ends.
private final class TemporaryRoot {
    let layout = StoreLayout(root: FileManager.default.temporaryDirectory
        .appending(path: "safira-\(UUID().uuidString)", directoryHint: .isDirectory))
    var downloads: URL { layout.root.appending(path: "Downloads", directoryHint: .isDirectory) }

    deinit { try? FileManager.default.removeItem(at: layout.root) }

    func files() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: downloads.path(percentEncoded: false))) ?? []).sorted()
    }
}

/// Downloads through the real WebKit, from a loopback server, into a folder of the test.
@MainActor
@Suite(.serialized) struct DownloadTests {
    /// Runs a test body with the registry of a fresh store, then releases it and removes the data stores it made.
    private func run(_ root: TemporaryRoot, _ body: (ProfileRegistry) async throws -> Void) async throws {
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            defer { ids = registry.profiles.map(\.id) }
            try await body(registry)
        }
        for id in ids { await removeDataStoreWhenReleased(id) }
    }

    /// The Active profile's owner, saving into the test's folder.
    private func profile(_ registry: ProfileRegistry, saving root: TemporaryRoot) -> ProfileContext {
        registry.active.web.downloadsDirectory = root.downloads
        return registry.active
    }

    private func isFinished(_ context: ProfileContext) -> Bool {
        !context.downloads.all.isEmpty && !context.downloads.hasActiveDownload
    }

    private func quarantine(_ file: URL) -> [String: Any]? {
        (try? file.resourceValues(forKeys: [.quarantinePropertiesKey]))?.quarantineProperties
    }

    @Test func aDownloadLinkIsSavedInTheDownloadsFolderAndListedInThePageProfileOnly() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = TemporaryRoot()
        try await run(root) { registry in
            let work = profile(registry, saving: root)
            let workID = registry.activeProfileID
            let personalID = registry.createProfile(name: "Personal", symbol: "🏠", searchEngine: .kagi)
            let personal = profile(registry, saving: root)
            registry.selectProfile(workID)

            work.session.submitCommandBar(server.url("/page.html").absoluteString)
            let tab = try #require(work.session.selectedTabID)
            let webView = try #require(work.web.webView(for: tab))
            try await waitUntil("the page loads") { webView.url == server.url("/page.html") && !webView.isLoading }
            _ = try await webView.evaluateJavaScript("document.getElementById('link').click()")
            try await waitUntil("the download is saved") { isFinished(work) }

            let saved = try #require(work.downloads.all.first)
            #expect(work.downloads.all.count == 1)
            #expect(saved.state == .completed)
            #expect(saved.fileName == "small.bin")
            #expect(saved.sourceURL == server.url("/small.bin"))
            #expect(saved.receivedBytes == 1000)
            #expect(saved.totalBytes == 1000)
            let file = root.downloads.appending(path: "small.bin")
            #expect(saved.savedFileURL()?.resolvingSymlinksInPath() == file.resolvingSymlinksInPath())
            #expect(try Data(contentsOf: file) == DownloadServer.bytes(0..<1000))
            #expect(root.files() == ["small.bin"])
            #expect(quarantine(file) != nil)
            #expect(personal.downloads.all == [])

            await registry.saveAll()
            #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: workID)).downloads().map(\.fileName) == ["small.bin"])
            #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: personalID)).downloads() == [])
        }
    }

    @Test func aLinkMarkedDownloadSavesAFileWebKitCouldShowAndTheTabKeepsItsPage() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = TemporaryRoot()
        try await run(root) { registry in
            let context = profile(registry, saving: root)
            context.session.submitCommandBar(server.url("/page.html").absoluteString)
            let tab = try #require(context.session.selectedTabID)
            let webView = try #require(context.web.webView(for: tab))
            try await waitUntil("the page loads") { webView.url == server.url("/page.html") && !webView.isLoading }

            _ = try await webView.evaluateJavaScript("document.getElementById('inline').click()")
            try await waitUntil("the file is saved") { isFinished(context) }

            #expect(context.downloads.all.map(\.fileName) == ["inline.txt"])
            #expect(try String(contentsOf: root.downloads.appending(path: "inline.txt"), encoding: .utf8) == "inline\n")
            #expect(webView.url == server.url("/page.html"))
            #expect(context.session.tabs.count == 1)
        }
    }

    @Test func eachProfileListsItsOwnDownloadsWhenBothDownloadTheSameFile() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = TemporaryRoot()
        try await run(root) { registry in
            let work = profile(registry, saving: root)
            registry.createProfile(name: "Personal", symbol: "🏠", searchEngine: .kagi)
            let personal = profile(registry, saving: root)

            work.session.submitCommandBar(server.url("/small.bin").absoluteString)
            try await waitUntil("the first Profile's download is saved") { isFinished(work) }
            personal.session.submitCommandBar(server.url("/small.bin").absoluteString)
            try await waitUntil("the second Profile's download is saved") { isFinished(personal) }

            #expect(work.downloads.all.map(\.fileName) == ["small.bin"])
            #expect(personal.downloads.all.map(\.fileName) == ["small 2.bin"])
            #expect(root.files() == ["small 2.bin", "small.bin"])
        }
    }

    @Test func aTypeWebKitCannotShowAndAnAttachmentAreSavedInsteadOfShown() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = TemporaryRoot()
        try await run(root) { registry in
            let context = profile(registry, saving: root)

            context.session.submitCommandBar(server.url("/small.bin").absoluteString)
            try await waitUntil("the binary file is saved") { isFinished(context) }
            context.session.submitCommandBar(server.url("/notes.txt").absoluteString)
            try await waitUntil("the attachment is saved") { context.downloads.all.count == 2 && isFinished(context) }

            #expect(context.downloads.all.map(\.fileName) == ["notes.txt", "small.bin"])
            #expect(try String(contentsOf: root.downloads.appending(path: "notes.txt"), encoding: .utf8) == "hello\n")
        }
    }

    @Test func cancellingKeepsAPartialFileAndRetryingContinuesItFromWhereItStopped() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = TemporaryRoot()
        try await run(root) { registry in
            let context = profile(registry, saving: root)

            context.session.submitCommandBar(server.url("/slow.bin").absoluteString)
            try await waitUntil("some bytes arrive") { (context.downloads.all.first?.receivedBytes ?? 0) >= 20_000 }
            let id = try #require(context.downloads.all.first?.id)
            await context.downloads.cancel(id)

            let cancelled = try #require(context.downloads.download(id))
            #expect(cancelled.state == .cancelled)
            #expect(cancelled.resumeData != nil)
            #expect(cancelled.receivedBytes >= 20_000)
            #expect(cancelled.receivedBytes < 100_000)
            #expect(root.files() == ["slow.bin.part"])

            #expect(context.downloads.retry(id))
            try await waitUntil("the download is saved", timeout: .seconds(20)) { isFinished(context) }

            let saved = try #require(context.downloads.download(id))
            #expect(context.downloads.all.count == 1)
            #expect(saved.state == .completed)
            #expect(saved.fileName == "slow.bin")
            #expect(saved.receivedBytes == 100_000)
            #expect(server.rangeRequests.count == 1)
            #expect(server.rangeRequests.first?.hasPrefix("bytes=") == true)
            #expect(root.files() == ["slow.bin"])
            let file = root.downloads.appending(path: "slow.bin")
            #expect(try Data(contentsOf: file) == DownloadServer.bytes(0..<100_000))
            #expect(quarantine(file) != nil)
        }
    }

    @Test func aTransferThatBreaksIsListedFailedAndRetryingItStartsOverFromTheBeginning() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = TemporaryRoot()
        try await run(root) { registry in
            let context = profile(registry, saving: root)

            context.session.submitCommandBar(server.url("/broken.bin").absoluteString)
            try await waitUntil("the download fails") { context.downloads.all.first?.state == .failed }
            let id = try #require(context.downloads.all.first?.id)
            #expect(context.downloads.all.first?.resumeData == nil)

            #expect(context.downloads.retry(id))
            try await waitUntil("the second transfer is made") { server.requestCount("/broken.bin") == 2 }
            try await waitUntil("the second transfer fails too") { context.downloads.all.first?.state == .failed }

            #expect(server.requestCount("/broken.bin") == 2)
            #expect(context.downloads.all.count == 1)
            #expect(context.downloads.all.first?.fileName == "broken.bin")
            #expect(server.rangeRequests == [])
        }
    }

    @Test func aDownloadSurvivesClosingItsTabAndTheTabsWebViewIsReleased() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = TemporaryRoot()
        try await run(root) { registry in
            let context = profile(registry, saving: root)

            context.session.submitCommandBar(server.url("/slow.bin").absoluteString)
            let tab = try #require(context.session.selectedTabID)
            try await waitUntil("some bytes arrive") { (context.downloads.all.first?.receivedBytes ?? 0) >= 20_000 }
            weak var released = context.web.webView(for: tab)
            #expect(released != nil)
            let before = try #require(context.downloads.all.first?.receivedBytes)

            context.session.close(tab)
            try await waitUntil("the Tab's web view is released") { released == nil }

            #expect(context.web.webView(for: tab) == nil)
            try await waitUntil("more bytes arrive after the Tab is gone", timeout: .seconds(5)) {
                (context.downloads.all.first?.receivedBytes ?? 0) > before
            }
            try await waitUntil("the download is saved", timeout: .seconds(20)) { isFinished(context) }
            #expect(context.downloads.all.first?.state == .completed)
            #expect(try Data(contentsOf: root.downloads.appending(path: "slow.bin")) == DownloadServer.bytes(0..<100_000))
        }
    }

    @Test func removingAStoppedDownloadDeletesItsPartialFileAndKeepsFinishedFiles() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = TemporaryRoot()
        try await run(root) { registry in
            let context = profile(registry, saving: root)
            context.session.submitCommandBar(server.url("/small.bin").absoluteString)
            try await waitUntil("the small file is saved") { isFinished(context) }
            context.session.submitCommandBar(server.url("/slow.bin").absoluteString)
            try await waitUntil("some bytes arrive") { (context.downloads.all.first?.receivedBytes ?? 0) >= 10_000 }
            let slow = try #require(context.downloads.all.first?.id)
            await context.downloads.cancel(slow)
            #expect(root.files() == ["slow.bin.part", "small.bin"])

            context.downloads.removeFinished()

            #expect(context.downloads.all == [])
            #expect(root.files() == ["small.bin"])
        }
    }

    @Test func deletingAProfileStopsItsDownloadsAndRemovesWhatTheyLeft() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = TemporaryRoot()
        try await run(root) { registry in
            let first = registry.activeProfileID
            let doomed = registry.createProfile(name: "Doomed", symbol: "💣", searchEngine: .kagi)
            // The Profile's owner is not kept here: holding it would keep its data store in use.
            let downloads = try await startSlowDownload(in: registry, root: root, server: server)

            try await registry.deleteProfile(doomed)

            #expect(registry.profiles.map(\.id) == [first])
            #expect(root.files() == [])
            #expect(downloads.hasActiveDownload == false)
        }
    }

    private func startSlowDownload(in registry: ProfileRegistry, root: TemporaryRoot, server: DownloadServer) async throws
        -> ProfileDownloads {
        let context = profile(registry, saving: root)
        context.session.submitCommandBar(server.url("/slow.bin").absoluteString)
        try await waitUntil("some bytes arrive") { (context.downloads.all.first?.receivedBytes ?? 0) >= 10_000 }
        return context.downloads
    }

    @Test func aPrivateWindowListsItsDownloadsInMemoryAndTheProfileDatabaseNeverHearsOfThem() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = TemporaryRoot()
        try await run(root) { registry in
            let profile = registry.activeProfileID
            let privateWindow = try #require(registry.makePrivateContext(attachedTo: profile))
            privateWindow.web.downloadsDirectory = root.downloads

            privateWindow.session.submitCommandBar(server.url("/small.bin").absoluteString)
            try await waitUntil("the download is saved") {
                !privateWindow.web.downloads.all.isEmpty && !privateWindow.web.downloads.hasActiveDownload
            }
            await registry.saveAll()

            #expect(privateWindow.web.downloads.all.map(\.fileName) == ["small.bin"])
            #expect(registry.active.downloads.all == [])
            #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: profile)).downloads() == [])
            await privateWindow.close()
        }
    }
}
