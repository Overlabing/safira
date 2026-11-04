// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import SafiraWeb
import Testing
import WebKit

/// Every file and folder under some roots, with its size, so two moments can be compared.
private struct Tree: Equatable {
    private(set) var entries: [String: Int] = [:]

    init(_ roots: [URL]) {
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let url as URL in walker {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                entries[url.path(percentEncoded: false)] = size
            }
        }
    }

    /// Paths present here and not in `earlier`.
    func newFiles(since earlier: Tree) -> [String] {
        entries.keys.filter { earlier.entries[$0] == nil }.sorted()
    }

    func changedFiles(since earlier: Tree) -> [String] {
        entries.filter { path, size in earlier.entries[path].map { $0 != size } ?? false }.keys.sorted()
    }
}

/// The files under `folders` that contain `token`, as ASCII or as UTF-16, which is how WebKit's databases and caches store
/// the strings a page writes.
private func filesContaining(_ token: String, in folders: [URL]) -> [String] {
    let needles = [Data(token.utf8), token.data(using: .utf16LittleEndian)!]
    var found: [String] = []
    for folder in folders {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            if needles.contains(where: { data.range(of: $0) != nil }) { found.append(url.path(percentEncoded: false)) }
        }
    }
    return found.sorted()
}

/// `writeEverything` with `token` as the value of the cookie, local storage and IndexedDB entries.
private func writing(_ token: String) -> String {
    writeEverything.replacingOccurrences(of: "\"A\"", with: "\"\(token)\"")
        .replacingOccurrences(of: "script=A", with: "script=\(token)")
}

/// A fresh Application Support folder for one test, removed when the test ends.
private final class TemporaryRoot {
    let layout = StoreLayout(root: FileManager.default.temporaryDirectory
        .appending(path: "safira-\(UUID().uuidString)", directoryHint: .isDirectory))

    deinit { try? FileManager.default.removeItem(at: layout.root) }
}

/// Where the process keeps what WebKit writes for it: the library folders of the app container when sandboxed, the
/// user's library otherwise (the test runner). Only the folders named for this process or for WebKit itself.
private func webKitFolders() -> [URL] {
    let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
    let bundle = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
    var folders: [URL] = []
    for area in ["WebKit", "Caches", "HTTPStorages"] {
        let area = library.appending(path: area, directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: area.path(percentEncoded: false))) ?? []
        folders += names.filter { $0.hasPrefix(bundle) || $0.hasPrefix("com.apple.WebKit") }.map {
            area.appending(path: $0, directoryHint: .isDirectory)
        }
    }
    return folders
}

/// A Private window beside its Profile: its data store, its session and what it leaves behind. Real WebKit.
@MainActor
@Suite(.serialized) struct PrivateWindowTests {
    @Test func aPrivateWindowAndItsProfileCannotSeeEachOthersWebsiteData() async throws {
        let server = try await StorageServer()
        let root = TemporaryRoot()
        var profile = ProfileID(rawValue: UUID())
        do {
            let registry = ProfileRegistry(layout: root.layout)
            profile = registry.activeProfileID
            let main = registry.active
            let privateWindow = try #require(registry.makePrivateContext(attachedTo: profile))

            let mainWriter = try await load(server.url("/cookie"), in: main.web)
            #expect(try await run(writeEverything, in: mainWriter) == "written")
            let privateReader = try await load(server.url("/"), in: privateWindow.web)
            #expect(try await read(in: privateReader) == .none)
            #expect(await privateWindow.web.dataStore.httpCookieStore.allCookies() == [])

            let privateWriter = try await load(server.url("/"), in: privateWindow.web)
            #expect(try await run(writeEverything.replacingOccurrences(of: "\"A\"", with: "\"P\"")
                .replacingOccurrences(of: "script=A", with: "script=P"), in: privateWriter) == "written")
            #expect(try await read(in: privateWriter).local == "P")
            #expect(await privateWindow.web.dataStore.httpCookieStore.allCookies().map(\.name).sorted() == ["script"])

            let mainReader = try await load(server.url("/"), in: main.web)
            let mainSees = try await read(in: mainReader)
            #expect(mainSees.cookie == "script=A")
            #expect(mainSees.local == "A")
            #expect(await main.web.dataStore.httpCookieStore.allCookies().map(\.name).sorted() == ["script", "server"])

            #expect(privateWindow.web.dataStore.isPersistent == false)
            #expect(privateWindow.web.dataStore.identifier == nil)
            #expect(privateWindow.web.dataStore !== main.web.dataStore)
            #expect(privateWriter.webView.configuration.websiteDataStore === privateWindow.web.dataStore)

            for page in [mainWriter, mainReader, privateReader, privateWriter] { page.close() }
            await privateWindow.close()
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func twoPrivateWindowsOfOneProfileDoNotSeeEachOthersWebsiteData() async throws {
        let server = try await StorageServer()
        var profile = ProfileID(rawValue: UUID())
        do {
            let registry = ProfileRegistry(layout: nil)
            profile = registry.activeProfileID
            let first = try #require(registry.makePrivateContext(attachedTo: profile))
            let second = try #require(registry.makePrivateContext(attachedTo: profile))
            let writer = try await load(server.url("/cookie"), in: first.web)
            #expect(try await run(writeEverything, in: writer) == "written")

            let reader = try await load(server.url("/"), in: second.web)
            #expect(try await read(in: reader) == .none)
            #expect(first.web.dataStore !== second.web.dataStore)

            writer.close()
            reader.close()
            await first.close()
            await second.close()
        }
        await removeDataStoreWhenReleased(profile)
    }

    /// The Profile's folder and its data store's folder are the Profile's alone, so they must not change at all. The
    /// folders WebKit shares with every other process of the test run cannot be told from other tests' writes by a
    /// tree comparison; there the proof is that nothing the Private window wrote, a token only it knows, is in any file.
    @Test func closingAPrivateWindowLeavesNoFileInTheProfileAndNothingOfItsDataAnywhere() async throws {
        let server = try await StorageServer()
        let root = TemporaryRoot()
        let token = "private-\(UUID().uuidString)"
        var profile = ProfileID(rawValue: UUID())
        do {
            let registry = ProfileRegistry(layout: root.layout)
            profile = registry.activeProfileID
            let main = registry.active
            let mainPage = try await load(server.url("/"), in: main.web)
            await registry.saveAll()
            mainPage.close()
            try await Task.sleep(for: .seconds(1))
            let storeFolders = webKitFolders().flatMap { folder in
                (try? FileManager.default.contentsOfDirectory(at: folder.appending(path: "WebsiteDataStore"),
                                                              includingPropertiesForKeys: nil)) ?? []
            }.filter { $0.lastPathComponent == profile.rawValue.uuidString }
            let profileFolders = [root.layout.profileDirectory(for: profile)] + storeFolders
            let before = Tree(profileFolders)

            let privateWindow = try #require(registry.makePrivateContext(attachedTo: profile))
            let writer = try await load(server.url("/cookie"), in: privateWindow.web)
            #expect(try await run(writing(token), in: writer) == "written")
            let session = privateWindow.session
            session.openCommandBar(for: .newTab)
            session.submitCommandBar(server.url("/").absoluteString)
            try await waitUntil("the Tab loads") { session.selectedTab?.state.title == "storage" }
            #expect(await privateWindow.web.dataStore.httpCookieStore.allCookies().map(\.value).contains(token))
            writer.close()
            await privateWindow.close()
            try await Task.sleep(for: .seconds(3))

            let after = Tree(profileFolders)
            #expect(after.newFiles(since: before) == [])
            #expect(after.changedFiles(since: before).filter { !$0.hasSuffix("-wal") && !$0.hasSuffix("-shm") } == [])
            #expect(filesContaining(token, in: [root.layout.root] + webKitFolders()) == [])
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func theSearchForAPagesDataFindsWhatAProfilesPagesWrite() async throws {
        let server = try await StorageServer()
        let root = TemporaryRoot()
        let token = "profile-\(UUID().uuidString)"
        var profile = ProfileID(rawValue: UUID())
        do {
            let registry = ProfileRegistry(layout: root.layout)
            profile = registry.activeProfileID
            var writer: WebKitPage? = try await load(server.url("/cookie"), in: registry.active.web)
            #expect(try await run(writing(token), in: try #require(writer)) == "written")
            await registry.saveAll()
            writer?.close()
            writer = nil
            var found: [String] = []
            for _ in 0..<150 where found.isEmpty {
                found = filesContaining(token, in: webKitFolders())
                if found.isEmpty { try await Task.sleep(for: .milliseconds(100)) }
            }
            #expect(found.isEmpty == false, "WebKit writes a Profile's data where the search looks")
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aPrivateWindowHasOneHiddenSpaceAndAddsNoOther() async throws {
        var profile = ProfileID(rawValue: UUID())
        do {
            let registry = ProfileRegistry(layout: nil)
            profile = registry.activeProfileID
            let privateWindow = try #require(registry.makePrivateContext(attachedTo: profile))

            #expect(privateWindow.session.hasSpaces == false)
            let only = privateWindow.session.activeSpaceID
            #expect(privateWindow.session.createSpace(name: "Work", emoji: "💼") == only)
            privateWindow.session.renameSpace(only, name: "Renamed", emoji: "🔥")
            #expect(privateWindow.session.spaces.map(\.id) == [only])
            #expect(privateWindow.session.spaces.map(\.name) == [ProfileSession.initialSpaceName])
            #expect(privateWindow.session.canDeleteSpace == false)
            #expect(registry.active.session.hasSpaces)
            await privateWindow.close()
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aPrivateWindowRecordsNoHistoryAndOffersNoneFromItsProfile() async throws {
        let server = try await StorageServer()
        let root = TemporaryRoot()
        var profile = ProfileID(rawValue: UUID())
        do {
            let registry = ProfileRegistry(layout: root.layout)
            profile = registry.activeProfileID
            let main = registry.active
            main.session.openCommandBar(for: .newTab)
            main.session.submitCommandBar(server.url("/main-visit").absoluteString)
            try await waitUntil("the Profile's Tab loads") { main.session.selectedTab?.state.title == "storage" }
            await main.saveNow()

            let privateWindow = try #require(registry.makePrivateContext(attachedTo: profile))
            let session = privateWindow.session
            session.openCommandBar(for: .newTab)
            session.submitCommandBar(server.url("/private-visit").absoluteString)
            try await waitUntil("the Private Tab loads") { session.selectedTab?.state.title == "storage" }
            await session.recordedHistorySettled()

            // The Profile's history has the Profile's visit and not the Private one.
            let database = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: profile))
            #expect(try await database.searchHistory("private-visit", limit: 10).isEmpty)
            #expect(try await database.searchHistory("main-visit", limit: 10).map(\.url.path) == ["/main-visit"])
            // The Private window finds its own open Tab, and nothing of the Profile's history.
            #expect(await session.suggestions(for: "main-visit").isEmpty)
            #expect(await session.suggestions(for: "private-visit").count == 1)
            // And the Profile's session does not see the Private window's Tab.
            #expect(await main.session.suggestions(for: "private-visit").isEmpty)

            await privateWindow.close()
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func theRegistryNeverListsAPrivateWindowSoNothingSearchedThroughItReachesOne() async throws {
        var profile = ProfileID(rawValue: UUID())
        do {
            let registry = ProfileRegistry(layout: nil)
            profile = registry.activeProfileID
            _ = registry.active
            let loadedBefore = registry.loadedContexts.map(\.id)
            let privateWindow = try #require(registry.makePrivateContext(attachedTo: profile))
            privateWindow.session.openCommandBar(for: .newTab)
            privateWindow.session.submitCommandBar("https://example.org/private")
            #expect(privateWindow.session.tabs.count == 1)

            #expect(registry.loadedContexts.map(\.id) == loadedBefore)
            #expect(registry.profiles.map(\.id) == [profile])
            #expect(registry.spaces(in: profile).flatMap(\.tabs).isEmpty)
            #expect(registry.active.session.tabs.isEmpty)
            #expect(registry.makePrivateContext(attachedTo: ProfileID(rawValue: UUID())) == nil)
            #expect(privateWindow.web.diagnostics == nil)
            #expect(privateWindow.web.isPrivate)
            #expect(registry.active.web.isPrivate == false)
            await privateWindow.close()
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aPrivateWindowStartsWithOnlyItsProfilesSearchEngineAndChoosingOneStaysInTheWindow() async throws {
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: nil)
            let first = registry.profiles[0].id
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            ids = [first, work]
            registry.active.webContentSettings.isAutoplayingSoundAllowed = true
            let fromWork = try #require(registry.makePrivateContext(attachedTo: work))

            #expect(fromWork.session.settings.searchEngine == .kagi)
            #expect(fromWork.session.settings.webContent == WebContentSettings())
            #expect(fromWork.parent.name == "Work")

            let withoutEngine = try #require(registry.makePrivateContext(attachedTo: first))
            #expect(withoutEngine.session.settings.searchEngine == nil)
            withoutEngine.session.chooseSearchEngine(.ecosia)
            #expect(withoutEngine.session.settings.searchEngine == .ecosia)
            #expect(registry.spaces(in: first).first?.tabs.isEmpty == true)
            registry.selectProfile(first)
            #expect(registry.active.session.settings.searchEngine == nil)

            await fromWork.close()
            await withoutEngine.close()
        }
        for id in ids { await removeDataStoreWhenReleased(id) }
    }

    @Test func aPrivateWindowRemembersSitePermissionsInMemoryAndNotInItsProfile() async throws {
        let root = TemporaryRoot()
        var profile = ProfileID(rawValue: UUID())
        do {
            let registry = ProfileRegistry(layout: root.layout)
            profile = registry.activeProfileID
            let privateWindow = try #require(registry.makePrivateContext(attachedTo: profile))
            let origin = try #require(SiteOrigin(scheme: "https", host: "meet.example.org"))
            privateWindow.web.permissionPrompt = { _ in PermissionAnswer(decision: .allow, remember: true) }
            #expect(await privateWindow.web.permissionDecision(requesting: [.camera], at: origin) == .allow)

            #expect(privateWindow.web.permissions.all.count == 1)
            #expect(registry.active.permissions.all.isEmpty)
            await privateWindow.close()
            let again = try #require(registry.makePrivateContext(attachedTo: profile))
            #expect(again.web.permissions.all.isEmpty)
            await again.close()
        }
        await removeDataStoreWhenReleased(profile)
    }

    // MARK: Helpers

    private func load(_ url: URL, in context: ProfileWebContext) async throws -> WebKitPage {
        let page = context.makePage(for: TabID())
        page.load(url, httpsFirst: false)
        try await waitUntil("\(url.path()) loads") {
            page.webView.url == url && !page.webView.isLoading && page.webView.title?.isEmpty == false
        }
        return page
    }

    private func run(_ script: String, in page: WebKitPage) async throws -> String? {
        try await page.webView.callAsyncJavaScript(script, contentWorld: .page) as? String
    }

    private func read(in page: WebKitPage) async throws -> StoredData {
        let json = try #require(try await run(readEverything, in: page))
        return try JSONDecoder().decode(StoredData.self, from: Data(json.utf8))
    }
}
