// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraStore
import SafiraWeb
import Testing
import WebKit

/// A fresh Application Support folder for one test, removed when the test ends.
private final class TemporaryRoot {
    let layout = StoreLayout(root: FileManager.default.temporaryDirectory
        .appending(path: "safira-\(UUID().uuidString)", directoryHint: .isDirectory))

    deinit { try? FileManager.default.removeItem(at: layout.root) }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }
}

/// The Profiles of the app, their owners, switching and deletion. The owners build real WebKit data stores.
@MainActor
@Suite(.serialized) struct ProfileRegistryTests {
    /// Releases the registry's owners and removes every data store it made.
    private func cleanUp(_ ids: [ProfileID]) async {
        for id in ids { await removeDataStoreWhenReleased(id) }
    }

    @Test func aFirstLaunchHasOneProfileWithNoSearchEngine() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            ids = registry.profiles.map(\.id)

            #expect(registry.profiles.map(\.name) == ["Default"])
            #expect(registry.activeProfileID == ids.first)
            #expect(registry.active.session.settings.searchEngine == nil)
            #expect(try AppDatabase(file: root.layout.appDatabaseFile).profiles() == registry.profiles)
        }
        await cleanUp(ids)
    }

    @Test func aNewProfileNeedsASearchEngineIsShownAndKeepsItsOwnSettings() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let first = registry.activeProfileID

            let work = registry.createProfile(name: "  Work ", symbol: "💼🏢", searchEngine: .kagi)
            ids = registry.profiles.map(\.id)

            #expect(registry.profiles.map { "\($0.symbol) \($0.name)" } == ["👤 Default", "💼 Work"])
            #expect(registry.activeProfileID == work)
            #expect(registry.active.session.settings.searchEngine == .kagi)
            #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work)).settings().searchEngine == .kagi)
            registry.selectProfile(first)
            #expect(registry.active.session.settings.searchEngine == nil)
        }
        await cleanUp(ids)
    }

    @Test func switchingByOffsetWrapsAroundAndTheActiveProfileComesBackAfterARelaunch() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let first = registry.activeProfileID
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            let school = registry.createProfile(name: "School", symbol: "🎓", searchEngine: .ecosia)
            ids = registry.profiles.map(\.id)

            registry.selectProfile(offset: 1)
            #expect(registry.activeProfileID == first)
            registry.selectProfile(offset: -1)
            #expect(registry.activeProfileID == school)
            registry.selectProfile(work)
            registry.renameProfile(work, name: "Office", symbol: "🏢")

            let relaunched = ProfileRegistry(layout: root.layout)
            #expect(relaunched.activeProfileID == work)
            #expect(relaunched.profiles.map { "\($0.symbol) \($0.name)" } == ["👤 Default", "🏢 Office", "🎓 School"])
        }
        await cleanUp(ids)
    }

    @Test func theCommandBarReachesTheActiveProfileOnlyAndAnInactiveProfileLoadsNothingUntilShown() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let first = registry.activeProfileID
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            ids = registry.profiles.map(\.id)

            registry.active.session.openCommandBar(for: .newTab)
            registry.active.session.submitCommandBar("about:blank")
            #expect(registry.active.session.tabs.count == 1)

            registry.selectProfile(first)
            #expect(registry.active.session.tabs.isEmpty)
            registry.active.session.submitCommandBar("report")
            #expect(registry.active.session.searchAwaitingEngine == "report")
            registry.active.session.cancelSearchEngineChoice()
            registry.selectProfile(work)
            #expect(registry.active.session.tabs.count == 1)
            #expect(registry.active.session.searchAwaitingEngine == nil)
            for context in registry.loadedContexts { context.session.closeAllTabs() }
        }
        await cleanUp(ids)
    }

    @Test func theLastProfileCannotBeDeleted() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            ids = registry.profiles.map(\.id)
            _ = registry.active
            #expect(!registry.canDeleteProfile)

            try await registry.deleteProfile(registry.activeProfileID)

            #expect(registry.profiles.map(\.id) == ids)
            #expect(root.exists(root.layout.profileDatabaseFile(for: ids[0])))
        }
        await cleanUp(ids)
    }

    @Test func deletingAProfileErasesItsDataStoreFolderAndDatabaseAndShowsAnother() async throws {
        let root = TemporaryRoot()
        let server = try await LocalServer.start(.http)
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let first = registry.activeProfileID
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            ids = registry.profiles.map(\.id)
            try await writeSomeData(in: registry, at: URL(string: "http://127.0.0.1:\(server.port)/")!)
            await registry.saveAll()
            #expect(await ProfileWebContext.dataStoreExists(for: work))
            #expect(root.exists(root.layout.profileDatabaseFile(for: work)))

            try await registry.deleteProfile(work)

            #expect(registry.profiles.map(\.id) == [first])
            #expect(registry.activeProfileID == first)
            #expect(!root.exists(root.layout.profileDirectory(for: work)))
            #expect(await !ProfileWebContext.dataStoreExists(for: work))
            let app = try AppDatabase(file: root.layout.appDatabaseFile)
            #expect(try app.profiles().map(\.id) == [first])
            #expect(try app.profilesPendingDeletion() == [])
            #expect(ProfileRegistry(layout: root.layout).profiles.map(\.id) == [first])
        }
        server.stop()
        await cleanUp(ids)
    }

    /// Opens a page in the Active profile and stores a cookie and local storage from it. The page stays open: deleting
    /// the Profile must close it.
    private func writeSomeData(in registry: ProfileRegistry, at url: URL) async throws {
        let session = registry.active.session
        session.openCommandBar(for: .newTab)
        session.submitCommandBar(url.absoluteString)
        let webView = try #require(session.selectedTabID.flatMap(registry.active.web.webView(for:)))
        try await waitUntil("the page loads") { webView.url == url && !webView.isLoading }
        _ = try await webView.callAsyncJavaScript("localStorage.setItem('k', 'v'); document.cookie = 'c=v'",
                                                  contentWorld: .page)
        #expect(await registry.active.web.dataStore.httpCookieStore.allCookies().map(\.name) == ["c"])
    }

    @Test func anEraseCutShortIsFinishedAtTheNextLaunch() async throws {
        let root = TemporaryRoot()
        let leftover = ProfileID(rawValue: UUID())
        var ids: [ProfileID] = []
        do {
            let app = try AppDatabase(file: root.layout.appDatabaseFile)
            try app.add(Profile(id: ProfileID(rawValue: UUID()), name: "Default"))
            try app.add(Profile(id: leftover, name: "Gone"))
            try ProfileDatabase(file: root.layout.profileDatabaseFile(for: leftover)).save(ProfileSettings(searchEngine: .kagi))
            try app.markForDeletion(leftover)

            let registry = ProfileRegistry(layout: root.layout)
            ids = registry.profiles.map(\.id)

            #expect(registry.profiles.map(\.name) == ["Default"])
            try await waitUntil("the leftover Profile is erased") {
                (try? app.profilesPendingDeletion()) == []
            }
            #expect(!root.exists(root.layout.profileDirectory(for: leftover)))
        }
        await cleanUp(ids)
    }
}
