// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CoreGraphics
import Foundation
import ImageIO
import Observation
import SafiraCore
import SafiraSession
import SafiraStore
import SafiraWeb
import Synchronization
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

    @Test func eachProfileKeepsItsOwnPaletteAcrossARelaunchAndANewOneDiffersFromTheOthers() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let first = registry.activeProfileID
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            let school = registry.createProfile(name: "School", symbol: "🎓", searchEngine: .ecosia, paletteID: "mint-cyan")
            let unknown = registry.createProfile(name: "Odd", symbol: "🧪", searchEngine: .ecosia, paletteID: "ocean")
            ids = registry.profiles.map(\.id)
            registry.renameProfile(first, name: "Default", symbol: "👤", paletteID: "purple-pink")
            registry.renameProfile(work, name: "Work", symbol: "💼")
            registry.renameProfile(unknown, name: "Odd", symbol: "🧪", paletteID: "ocean")

            #expect(registry.profiles.map(\.paletteID) == ["purple-pink", "orange-pink", "mint-cyan", "teal-green"])
            let relaunched = ProfileRegistry(layout: root.layout)
            #expect(relaunched.profiles.map(\.paletteID) == ["purple-pink", "orange-pink", "mint-cyan", "teal-green"])
            #expect(relaunched.profiles.first { $0.id == school }?.paletteID == "mint-cyan")
        }
        await cleanUp(ids)
    }

    @Test func aFirstLaunchProfileHasTheFirstTheme() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            ids = registry.profiles.map(\.id)

            #expect(registry.activeProfile.paletteID == "indigo-blue")
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

    @Test func anExternalLinkOpensInTheChosenProfileAndShowsIt() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let first = registry.activeProfileID
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            registry.selectProfile(first)
            ids = registry.profiles.map(\.id)

            let opened = registry.openExternalLink(try #require(URL(string: "about:blank")), in: work)

            #expect(opened)
            #expect(registry.activeProfileID == work)
            #expect(registry.active.session.tabs.count == 1)
            #expect(registry.active.session.selectedTabID == registry.active.session.tabs.first?.id)
            registry.selectProfile(first)
            #expect(registry.active.session.tabs.isEmpty)
            for context in registry.loadedContexts { context.session.closeAllTabs() }
        }
        await cleanUp(ids)
    }

    @Test func anExternalLinkOpensInTheNamedSpaceOfTheProfile() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let first = registry.activeProfileID
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            let docs = registry.active.session.createSpace(name: "Docs", emoji: "📄")
            let home = try #require(registry.active.session.spaces.first?.id)
            registry.active.session.selectSpace(home)
            registry.selectProfile(first)
            ids = registry.profiles.map(\.id)

            let opened = registry.openExternalLink(try #require(URL(string: "about:blank")), in: work, space: docs)

            #expect(opened)
            #expect(registry.activeProfileID == work)
            #expect(registry.active.session.activeSpaceID == docs)
            #expect(registry.active.session.spaces.map(\.tabs.count) == [0, 1])
            for context in registry.loadedContexts { context.session.closeAllTabs() }
        }
        await cleanUp(ids)
    }

    @Test func anExternalLinkForASpaceThatDoesNotExistChangesNothing() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let first = registry.activeProfileID
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            registry.selectProfile(first)
            ids = registry.profiles.map(\.id)

            let opened = registry.openExternalLink(try #require(URL(string: "about:blank")), in: work, space: SpaceID())

            #expect(!opened)
            #expect(registry.activeProfileID == first)
            #expect(registry.active.session.tabs.isEmpty)
            for context in registry.loadedContexts { context.session.closeAllTabs() }
        }
        await cleanUp(ids)
    }

    @Test func theSpacesOfAProfileAreListedWithoutShowingIt() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let first = registry.activeProfileID
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            registry.active.session.createSpace(name: "Docs", emoji: "📄")
            registry.selectProfile(first)
            ids = registry.profiles.map(\.id)

            #expect(registry.spaces(in: work).map(\.name) == ["Home", "Docs"])
            #expect(registry.activeProfileID == first)
            #expect(registry.spaces(in: ProfileID(rawValue: UUID())).isEmpty)
            for context in registry.loadedContexts { context.session.closeAllTabs() }
        }
        await cleanUp(ids)
    }

    /// The Space rail's menu on another Profile's Space or dot: the command reaches that Profile's own owner, created
    /// without showing it, and the rail, which read the Profile's saved Spaces, is told to read its session instead.
    @Test func aSpaceOfAProfileNotShownIsReachedWithoutShowingItAndTheRailSeesTheChange() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let first = registry.activeProfileID
            registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            registry.active.session.createSpace(name: "Docs", emoji: "📄")
            registry.selectProfile(first)
            ids = registry.profiles.map(\.id)
            await registry.saveAll()
        }
        do {
            let relaunched = ProfileRegistry(layout: root.layout)
            let first = relaunched.activeProfileID
            let work = try #require(ids.last)
            #expect(!relaunched.loadedContexts.contains { $0.id == work }, "Work is not loaded after the relaunch")
            let saved = relaunched.spaceSummary(of: work).spaces
            #expect(saved.map(\.name) == ["Home", "Docs"])
            let docs = try #require(saved.last?.id)

            let told = Mutex(false)
            withObservationTracking { _ = relaunched.spaceSummary(of: work) } onChange: { told.withLock { $0 = true } }
            let context = try #require(relaunched.context(ofSpace: docs))
            #expect(context.id == work)
            #expect(told.withLock { $0 }, "loading Work tells whoever read its saved Spaces")
            context.session.moveSpace(docs, by: -1)

            #expect(relaunched.spaceSummary(of: work).spaces.map(\.name) == ["Docs", "Home"])
            #expect(relaunched.activeProfileID == first, "Work was not shown")
            #expect(relaunched.context(of: work) === context)
            #expect(relaunched.context(of: ProfileID(rawValue: UUID())) == nil)
            #expect(relaunched.context(ofSpace: SpaceID(rawValue: UUID())) == nil)
            for context in relaunched.loadedContexts { context.session.closeAllTabs() }
        }
        await cleanUp(ids)
    }

    @Test func anExternalLinkForAProfileThatDoesNotExistChangesNothing() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            ids = registry.profiles.map(\.id)

            let opened = registry.openExternalLink(try #require(URL(string: "about:blank")),
                                                   in: ProfileID(rawValue: UUID()))

            #expect(!opened)
            #expect(registry.active.session.tabs.isEmpty)
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
        let store = registry.active.web.dataStore.httpCookieStore
        try await waitUntilAsync("the cookie is stored") { await store.allCookies().map(\.name) == ["c"] }
        #expect(await store.allCookies().map(\.name) == ["c"])
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

    /// The whole path with real pages: each Profile records the pages its own Tabs load, suggestions follow the Active
    /// profile when it changes, and computing them sends nothing to the servers.
    @Test func suggestionsFollowTheActiveProfileAndTypingSendsNoRequest() async throws {
        let personalServer = try await LocalServer.start(.http, title: "Caf&#233; menu of the week")
        let workServer = try await LocalServer.start(.http, title: "Quarterly roadmap")
        defer { personalServer.stop(); workServer.stop() }
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: nil)
            let personal = registry.activeProfileID
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            ids = registry.profiles.map(\.id)
            func open(_ server: LocalServer, titled title: String) async throws -> TabID {
                let session = registry.active.session
                session.openCommandBar(for: .newTab)
                session.submitCommandBar("http://127.0.0.1:\(server.port)/")
                let tab = try #require(session.selectedTab)
                try await waitUntil("the page \(title) has loaded") { tab.state.title == title && !tab.state.isLoading }
                return tab.id
            }
            func suggested(_ text: String) async -> [String] {
                await registry.active.session.suggestions(for: text).map {
                    switch $0.kind {
                    case .openTab: "tab: \($0.title)"
                    case .history: "history: \($0.title)"
                    }
                }
            }

            let roadmap = try await open(workServer, titled: "Quarterly roadmap")
            registry.selectProfile(personal)
            _ = try await open(personalServer, titled: "Café menu of the week")
            let requestsAfterLoading = (personalServer.requestCount, workServer.requestCount)

            #expect(await suggested("cafe") == ["tab: Café menu of the week"])
            #expect(await suggested("QUARTERLY").isEmpty)
            for typed in ["c", "ca", "caf", "café", "café m", "quarterly", "https://example.com", "x y z"] {
                _ = await suggested(typed)
            }

            registry.selectProfile(work)
            #expect(registry.activeProfileID == work)
            #expect(await suggested("quarterly") == ["tab: Quarterly roadmap"])
            #expect(await suggested("cafe").isEmpty)

            registry.active.session.close(roadmap)
            #expect(await suggested("quarterly") == ["history: Quarterly roadmap"])
            registry.selectProfile(personal)
            #expect(await suggested("quarterly").isEmpty)
            #expect(await suggested("cafe") == ["tab: Café menu of the week"])

            #expect((personalServer.requestCount, workServer.requestCount) == requestsAfterLoading)
            for context in registry.loadedContexts { context.session.closeAllTabs() }
        }
        await cleanUp(ids)
    }

    /// The whole path of "Clear history and website data": two Profiles signed in to the same local site, one cleared
    /// for all time. It is signed out and no longer suggests a page it only remembers; its Spaces, Tabs and settings
    /// stay; the other Profile keeps its login and its history.
    @Test func clearingAllTimeSignsOutOneProfileAndKeepsItsTabsSpacesAndSettingsAndTheOtherProfileUntouched() async throws {
        let root = TemporaryRoot()
        let server = try await LocalServer.start(.http, title: "Quarterly roadmap")
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let personal = registry.activeProfileID
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            ids = registry.profiles.map(\.id)
            func open(_ path: String, in context: ProfileContext) async throws -> TabID {
                context.session.openCommandBar(for: .newTab)
                context.session.submitCommandBar("http://127.0.0.1:\(server.port)\(path)")
                let tab = try #require(context.session.selectedTab)
                try await waitUntil("\(path) has loaded") { tab.state.title == "Quarterly roadmap" && !tab.state.isLoading }
                return tab.id
            }
            func signIn(_ context: ProfileContext, through tab: TabID) async throws {
                let webView = try #require(context.web.webView(for: tab))
                _ = try await webView.callAsyncJavaScript(
                    "document.cookie = 'session=signed-in; path=/'; localStorage.setItem('user', 'me')", contentWorld: .page)
            }
            func cookies(_ context: ProfileContext) async -> [String] {
                await context.web.dataStore.httpCookieStore.allCookies().map { "\($0.name)=\($0.value)" }
            }
            func suggested(_ context: ProfileContext) async -> [String] {
                await context.session.suggestions(for: "roadmap").map {
                    switch $0.kind {
                    case .openTab: "tab: \($0.address.path())"
                    case .history: "history: \($0.address.path())"
                    }
                }
            }

            let workContext = registry.active
            let home = try await open("/home", in: workContext)
            try await signIn(workContext, through: home)
            let reading = workContext.session.createSpace(name: "Reading", emoji: "📚")
            _ = try await open("/reading", in: workContext)
            let visited = try await open("/visited", in: workContext)
            workContext.session.close(visited)
            registry.selectProfile(personal)
            let personalContext = registry.active
            let personalTab = try await open("/home", in: personalContext)
            try await signIn(personalContext, through: personalTab)
            registry.selectProfile(work)

            try await waitUntilAsync("the first Profile's cookie is stored") { await cookies(workContext) == ["session=signed-in"] }
            try await waitUntilAsync("the second Profile's cookie is stored") { await cookies(personalContext) == ["session=signed-in"] }
            #expect(await cookies(workContext) == ["session=signed-in"])
            #expect(await suggested(workContext) == ["tab: /reading", "tab: /home", "history: /visited"])

            try await workContext.clearBrowsingData(.allTime)

            #expect(await cookies(workContext) == [])
            #expect(await suggested(workContext) == ["tab: /reading", "tab: /home"])
            #expect(workContext.session.spaces.map(\.name) == ["Home", "Reading"])
            #expect(workContext.session.spaces.map { $0.tabs.count } == [1, 1])
            #expect(workContext.session.activeSpaceID == reading)
            #expect(workContext.session.settings.searchEngine == .kagi)
            #expect(await cookies(personalContext) == ["session=signed-in"])
            #expect(await suggested(personalContext) == ["tab: /home"])
            personalContext.session.close(personalTab)
            #expect(await suggested(personalContext) == ["history: /home"])
            for context in registry.loadedContexts { context.session.closeAllTabs() }
        }
        server.stop()
        await cleanUp(ids)
    }
}

/// The first launch: onboarding is pending exactly when the launch created the first Profile.
extension ProfileRegistryTests {
    @Test func aFirstLaunchHasOnboardingPendingUntilItIsCompletedAndTheFirstProfileTakesTheChoices() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            ids = registry.profiles.map(\.id)
            #expect(registry.isOnboardingPending)
            #expect(ProfileRegistry(layout: root.layout).isOnboardingPending, "cut short, it is offered again")

            registry.completeOnboarding(name: "  Work ", symbol: "💼🏢", searchEngine: .kagi,
                                        webContent: WebContentSettings(isFraudulentSiteWarningEnabled: false,
                                                                       isAutoplayingSoundAllowed: true))
            await registry.saveAll()

            #expect(registry.isOnboardingPending == false)
            #expect(registry.profiles.map { "\($0.symbol) \($0.name)" } == ["💼 Work"])
            #expect(registry.profiles.map(\.id) == ids)
            let relaunched = ProfileRegistry(layout: root.layout)
            #expect(relaunched.isOnboardingPending == false)
            #expect(relaunched.profiles.map { "\($0.symbol) \($0.name)" } == ["💼 Work"])
            let saved = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: ids[0])).settings()
            #expect(saved.searchEngine == .kagi)
            #expect(saved.webContent == WebContentSettings(isFraudulentSiteWarningEnabled: false,
                                                           isAutoplayingSoundAllowed: true))
        }
        await cleanUp(ids)
    }

    @Test func anAppThatAlreadyHadAProfileNeverGetsAnOnboardingAndCompletingChangesNothing() async throws {
        let root = TemporaryRoot()
        let existing = Profile(id: ProfileID(rawValue: UUID()), name: "Mine", symbol: "🏠")
        try AppDatabase(file: root.layout.appDatabaseFile).add(existing)
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            ids = registry.profiles.map(\.id)
            #expect(registry.isOnboardingPending == false)

            registry.completeOnboarding(name: "Other", symbol: "💼", searchEngine: .kagi, webContent: WebContentSettings())

            #expect(registry.profiles == [existing])
            #expect(registry.active.session.settings.searchEngine == nil)
        }
        await cleanUp(ids)
    }

    @Test func aDeletedProfileDoesNotBringOnboardingBack() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            registry.completeOnboarding(name: "One", symbol: "1", searchEngine: .google, webContent: WebContentSettings())
            let second = registry.createProfile(name: "Two", symbol: "2", searchEngine: .ecosia)
            ids = registry.profiles.map(\.id)
            try await registry.deleteProfile(second)

            #expect(ProfileRegistry(layout: root.layout).isOnboardingPending == false)
        }
        await cleanUp(ids)
    }
}

private typealias MailScheme = SafiraCore.URLScheme

/// What each Profile remembers about sites and apps stays in that Profile, and what clearing Browsing data keeps.
extension ProfileRegistryTests {
    @Test func twoProfilesNeverShareOneSitePermissionsAndWhatOneRemembersIsUnknownToTheOther() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let work = registry.active
            let personal = registry.createProfile(name: "Personal", symbol: "🏠", searchEngine: .kagi)
            let home = registry.active
            ids = registry.profiles.map(\.id)
            let meet = try #require(SiteOrigin(identifier: "https://meet.example"))
            let mail = try #require(MailScheme("mailto"))

            #expect(work.permissions !== home.permissions)
            #expect(work.web.permissions === work.permissions)
            #expect(work.session.appLinks.permissions === work.permissions)
            #expect(home.session.appLinks.permissions === home.permissions)

            work.permissions.remember(.allow, for: [.camera], at: meet)
            work.permissions.rememberAppLink(.allow, for: mail)

            #expect(home.permissions.all.isEmpty)
            #expect(home.permissions.appLinks.isEmpty)
            home.web.permissionPrompt = nil
            #expect(await home.web.permissionDecision(requesting: [.camera], at: meet) == .deny)
            #expect(await work.web.permissionDecision(requesting: [.camera], at: meet) == .allow)
            #expect(home.permissions.appLinkDecision(for: mail) == nil)
            #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: personal)).sitePermissions().isEmpty)
            #expect(try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work.id)).sitePermissions().count == 1)
        }
        await cleanUp(ids)
    }

    @Test func clearingAllTimeKeepsPinnedTabsFoldersAndSitePermissionsInMemoryAndOnDisk() async throws {
        let root = TemporaryRoot()
        let server = try await LocalServer.start(.http, title: "Quarterly roadmap")
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let context = registry.active
            ids = registry.profiles.map(\.id)
            let session = context.session
            session.openCommandBar(for: .newTab)
            session.submitCommandBar("http://127.0.0.1:\(server.port)/pinned")
            let tab = try #require(session.selectedTab)
            try await waitUntil("the page has loaded") { tab.state.title == "Quarterly roadmap" && !tab.state.isLoading }
            session.pin(tab.id)
            _ = try #require(session.createFolder(name: "Docs"))
            let meet = try #require(SiteOrigin(identifier: "https://meet.example"))
            let mail = try #require(MailScheme("mailto"))
            context.permissions.remember(.allow, for: [.camera, .location], at: meet)
            context.permissions.rememberAppLink(.deny, for: mail)
            await context.saveNow()
            let pinnedAddress = URL(string: "http://127.0.0.1:\(server.port)/pinned")

            try await context.clearBrowsingData(.allTime)
            await context.saveNow()

            let space = try #require(session.spaces.first)
            #expect(space.pinnedTabs.map(\.id) == [tab.id])
            #expect(space.pinnedTabs.first?.pinnedAddress == pinnedAddress)
            #expect(session.pinnedItems.count == 2)
            #expect(context.permissions.all.map(\.kind) == [.camera, .location])
            #expect(context.permissions.appLinkDecision(for: mail) == .deny)
            let saved = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: context.id))
            let savedSpace = try #require(saved.savedSession().spaces.first)
            #expect(savedSpace.pinned.pinnedTabs.map(\.id) == [tab.id])
            #expect(savedSpace.pinned.count == 2)
            #expect(try saved.sitePermissions().map(\.kind) == [.camera, .location])
            #expect(try saved.appLinkChoices().map(\.scheme) == [mail])
            for context in registry.loadedContexts { context.session.closeAllTabs() }
        }
        server.stop()
        await cleanUp(ids)
    }
}

/// A site that answers every icon request with one PNG, standing in for a loaded page's fetches.
@MainActor
private final class IconSite: SiteResourceFetcher {
    private(set) var fetched: [URL] = []

    func fetchSiteResource(_ url: URL, byteLimit: Int) async -> SiteResourceResponse {
        fetched.append(url)
        let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return .resource(data as Data, cacheControl: nil)
    }
}

/// Site icons belong to one Profile: they live in its own folder, and its Clear history and website data removes them.
extension ProfileRegistryTests {
    @Test func siteIconsLiveInTheirProfilesFolderAndAreClearedWithItsBrowsingData() async throws {
        let root = TemporaryRoot()
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: root.layout)
            let personal = registry.activeProfileID
            let work = registry.createProfile(name: "Work", symbol: "💼", searchEngine: .kagi)
            ids = registry.profiles.map(\.id)
            let workContext = registry.active
            registry.selectProfile(personal)
            let personalContext = registry.active
            let site = URL(string: "https://docs.example/")!
            let workSite = IconSite()
            let personalSite = IconSite()
            func folder(_ id: ProfileID) -> URL {
                root.layout.profileDirectory(for: id).appending(path: "SiteIcons", directoryHint: .isDirectory)
            }
            func files(_ id: ProfileID) -> [String] {
                let path = folder(id).path(percentEncoded: false)
                return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).sorted()
            }

            #expect(workContext.session.siteIcons.directory == folder(work))
            workContext.session.siteIcons.pageLoaded(PageIconLinks(page: site, base: site, tags: []), fetcher: workSite)
            await workContext.session.siteIcons.settled()

            #expect(workContext.session.siteIcons.icon(for: site)?.width == 16)
            #expect(files(work) == ["https%3A%2F%2Fdocs.example.expires", "https%3A%2F%2Fdocs.example.png"])
            #expect(personalContext.session.siteIcons.icon(for: site) == nil)
            await personalContext.session.siteIcons.settled()
            #expect(personalContext.session.siteIcons.icon(for: site) == nil, "never read from another Profile")
            #expect(files(personal) == [])

            personalContext.session.siteIcons.pageLoaded(PageIconLinks(page: site, base: site, tags: []),
                                                         fetcher: personalSite)
            await personalContext.session.siteIcons.settled()
            #expect(personalSite.fetched.count == 1, "the Personal Profile fetches for itself")

            try await workContext.clearBrowsingData(.allTime)

            #expect(workContext.session.siteIcons.icon(for: site) == nil)
            await workContext.session.siteIcons.settled()
            #expect(workContext.session.siteIcons.icon(for: site) == nil)
            #expect(files(work) == [])
            #expect(personalContext.session.siteIcons.icon(for: site)?.width == 16)
            #expect(files(personal) == ["https%3A%2F%2Fdocs.example.expires", "https%3A%2F%2Fdocs.example.png"])
            for context in registry.loadedContexts { context.session.closeAllTabs() }
        }
        await cleanUp(ids)
    }
}
