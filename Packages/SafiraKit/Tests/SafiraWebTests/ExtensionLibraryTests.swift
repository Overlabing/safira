// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraStore
@testable import SafiraWeb
import Testing
import WebKit

/// Installing, switching per Profile, updating and removing extensions, on real WebKit. Every Profile is `.inMemory`
/// (non-persistent data store and extension state) and no extension stores a `CryptoKey`, so nothing reaches the
/// keychain; the list itself goes to a temporary `app.sqlite`. The extensions are written by the tests.
@MainActor
@Suite(.serialized, .oneWebKitTestAtATime) struct ExtensionLibraryTests {
    static let fixtureID = "pfikphmpnbnmihdgfbljkjgfnamcpjme"

    @Test func anInstallAsksOnceThenRunsInEveryProfileUnderItsKeyIdentifier() async throws {
        let place = try Place()
        defer { place.clean() }
        let folder = try place.extensionFolder()
        let server = try await AnyHostServer.start()
        let work = try ExtensionHostTests.profile()
        let personal = try ExtensionHostTests.profile()
        let library = place.library()
        await library.attach(try #require(work.extensions), profile: work.id)
        await library.attach(try #require(personal.extensions), profile: personal.id)
        var asked: [ExtensionPermissionRequest] = []

        let installed = try await library.install(from: folder) { asked.append($0); return true }

        #expect(asked.count == 1)
        #expect(asked.first?.moment == .install)
        #expect(asked.first?.permissions == ["activeTab", "alarms", "storage"])
        #expect(asked.first?.matchPatterns == ["http://127.0.0.1/*", "http://localhost/*", "https://*/*"])
        #expect(asked.first?.hasAccessToAllHosts == true)
        #expect(asked.first?.summary.first == "Can read and modify webpages on all websites")
        #expect(installed?.id == Self.fixtureID)
        #expect(installed?.grantedPermissions == ["activeTab", "alarms", "storage"])
        #expect(try #require(work.extensions).loadedExtensions.map(\.identifier) == [Self.fixtureID])
        #expect(try #require(personal.extensions).loadedExtensions.map(\.identifier) == [Self.fixtureID])
        let context = try #require(work.extensions?.controller.extensionContexts.first)
        #expect(context.baseURL == URL(string: "webkit-extension://\(Self.fixtureID)/"))
        #expect(context.currentPermissions.map(\.rawValue).sorted() == ["activeTab", "alarms", "storage"])

        let tab = work.session.openExternalLink(server.url(host: "127.0.0.1"))
        try await ExtensionHostTests.waitUntilLoaded(work, tab)
        try await waitUntilAsync("the content script ran in the Work Profile") {
            await ExtensionHostTests.evaluate("String(document.documentElement.dataset.isolated)", in: work, tab) == "isolated"
        }

        let reopened = place.library()
        #expect(reopened.installed.map(\.id) == [Self.fixtureID])
        #expect(reopened.installed.first?.version == "1.2.3")
        server.stop()
    }

    @Test func cancellingThePermissionSheetInstallsNothing() async throws {
        let place = try Place()
        defer { place.clean() }
        let profile = try ExtensionHostTests.profile()
        let library = place.library()
        await library.attach(try #require(profile.extensions), profile: profile.id)

        let folderResult = try await library.install(from: try place.extensionFolder()) { _ in false }
        let zipResult = try await library.install(from: try place.zip(of: place.extensionFolder(key: nil))) { _ in false }

        #expect(folderResult == nil)
        #expect(zipResult == nil)
        #expect(library.installed.isEmpty)
        #expect(try #require(profile.extensions).loadedExtensions.isEmpty)
        #expect(try AppDatabase(file: place.databaseFile).installedExtensions().isEmpty)
        #expect(place.copies().isEmpty)
    }

    @Test func aZipIsCopiedAndACRXTakesTheIdentifierItsHeaderNames() async throws {
        let place = try Place()
        defer { place.clean() }
        let profile = try ExtensionHostTests.profile()
        let library = place.library()
        await library.attach(try #require(profile.extensions), profile: profile.id)
        let zip = try place.zip(of: place.extensionFolder(key: nil, name: "Zipped"))
        let crxFile = place.root.appending(path: "packed.crx")
        let crxZip = try Data(contentsOf: place.zip(of: place.extensionFolder(key: nil, name: "Packed")))
        try ExtensionPackageTests.crx(zip: crxZip, crxID: ExtensionPackageTests.ascending).write(to: crxFile)

        let zipped = try #require(try await library.install(from: zip) { _ in true })
        let packed = try #require(try await library.install(from: crxFile) { _ in true })

        #expect(UUID(uuidString: zipped.id) != nil)
        #expect(zipped.source == .archive(fileName: "\(zipped.id).zip"))
        #expect(packed.id == "aaabacadaeafagahaiajakalamanaoap")
        #expect(packed.source == .archive(fileName: "aaabacadaeafagahaiajakalamanaoap.zip"))
        #expect(place.copies() == ["\(zipped.id).zip", "aaabacadaeafagahaiajakalamanaoap.zip"].sorted())
        #expect(try #require(profile.extensions).loadedExtensions.map(\.displayName) == ["Packed", "Zipped"])
        await #expect(throws: ExtensionInstallError.alreadyInstalled(name: "Packed")) {
            try await library.install(from: crxFile) { _ in true }
        }

        // The copy is what runs after a relaunch: the file the user chose may be gone.
        try FileManager.default.removeItem(at: zip)
        let later = try ExtensionHostTests.profile()
        await place.library().attach(try #require(later.extensions), profile: later.id)
        #expect(try #require(later.extensions).loadedExtensions.map(\.displayName) == ["Packed", "Zipped"])
    }

    @Test func aProfileSwitchedOffStopsInjectingThereAndRemoveTakesItOutOfEveryProfile() async throws {
        let place = try Place()
        defer { place.clean() }
        let folder = try place.extensionFolder()
        let server = try await AnyHostServer.start()
        let work = try ExtensionHostTests.profile()
        let personal = try ExtensionHostTests.profile()
        let library = place.library()
        await library.attach(try #require(work.extensions), profile: work.id)
        await library.attach(try #require(personal.extensions), profile: personal.id)
        try await library.install(from: folder) { _ in true }
        let workHost = try #require(work.extensions)
        let personalHost = try #require(personal.extensions)

        await library.setEnabled(false, extension: Self.fixtureID, in: personal.id)

        #expect(library.installed.first?.disabledProfiles == [personal.id])
        #expect(try AppDatabase(file: place.databaseFile).installedExtensions().first?.disabledProfiles == [personal.id])
        #expect(personalHost.loadedExtensions.isEmpty)
        #expect(workHost.loadedExtensions.map(\.identifier) == [Self.fixtureID])
        let mark = "String(document.documentElement.dataset.isolated)"
        let workTab = work.session.openExternalLink(server.url(host: "127.0.0.1"))
        let personalTab = personal.session.openExternalLink(server.url(host: "127.0.0.1"))
        try await ExtensionHostTests.waitUntilLoaded(work, workTab)
        try await ExtensionHostTests.waitUntilLoaded(personal, personalTab)
        try await waitUntilAsync("the content script ran in the Work Profile") {
            await ExtensionHostTests.evaluate(mark, in: work, workTab) == "isolated"
        }
        #expect(await ExtensionHostTests.evaluate(mark, in: personal, personalTab) == "undefined")

        await library.remove(Self.fixtureID)

        #expect(library.installed.isEmpty)
        #expect(workHost.loadedExtensions.isEmpty)
        #expect(personalHost.loadedExtensions.isEmpty)
        #expect(try AppDatabase(file: place.databaseFile).installedExtensions().isEmpty)
        let afterRemoval = work.session.openExternalLink(server.url(host: "127.0.0.1"))
        try await ExtensionHostTests.waitUntilLoaded(work, afterRemoval)
        #expect(await ExtensionHostTests.evaluate(mark, in: work, afterRemoval) == "undefined")
        server.stop()
    }

    @Test func turningAProfileBackOnLoadsItThereAgain() async throws {
        let place = try Place()
        defer { place.clean() }
        let profile = try ExtensionHostTests.profile()
        let library = place.library()
        await library.attach(try #require(profile.extensions), profile: profile.id)
        try await library.install(from: try place.extensionFolder()) { _ in true }

        await library.setEnabled(false, extension: Self.fixtureID, in: profile.id)
        #expect(try #require(profile.extensions).loadedExtensions.isEmpty)
        await library.setEnabled(true, extension: Self.fixtureID, in: profile.id)

        #expect(try #require(profile.extensions).loadedExtensions.map(\.identifier) == [Self.fixtureID])
        #expect(library.installed.first?.disabledProfiles == [])
        // A Profile attached later gets every extension whose switch it never turned off.
        let later = try ExtensionHostTests.profile()
        await library.attach(try #require(later.extensions), profile: later.id)
        #expect(try #require(later.extensions).loadedExtensions.map(\.identifier) == [Self.fixtureID])
    }

    /// `permissions.request` reaches the delegate; what the user allows is kept and given in every Profile.
    @Test func aRunTimeRequestAsksWithTheSameSheetAndAllowsInEveryProfile() async throws {
        let place = try Place()
        defer { place.clean() }
        let work = try ExtensionHostTests.profile()
        let personal = try ExtensionHostTests.profile()
        let library = place.library()
        await library.attach(try #require(work.extensions), profile: work.id)
        await library.attach(try #require(personal.extensions), profile: personal.id)
        try await library.install(from: try place.extensionFolder()) { _ in true }
        let workHost = try #require(work.extensions)
        let context = try #require(workHost.controller.extensionContexts.first)
        var asked: [ExtensionPermissionRequest] = []
        library.permissionPrompt = { asked.append($0); return $0.permissions == ["tabs"] }

        let allowed: Set<WKWebExtension.Permission> = await withCheckedContinuation { done in
            workHost.webExtensionController(workHost.controller, promptForPermissions: [.tabs], in: nil,
                                            for: context) { granted, _ in done.resume(returning: granted) }
        }
        let refused: Set<WKWebExtension.Permission> = await withCheckedContinuation { done in
            workHost.webExtensionController(workHost.controller, promptForPermissions: [.cookies], in: nil,
                                            for: context) { granted, _ in done.resume(returning: granted) }
        }

        #expect(allowed == [.tabs])
        #expect(refused == [])
        #expect(asked.map(\.moment) == [.runtime, .runtime])
        #expect(asked.first?.summary == ["Can see the address and title of your Tabs"])
        #expect(library.installed.first?.grantedPermissions == ["activeTab", "alarms", "storage", "tabs"])
        #expect(try AppDatabase(file: place.databaseFile).installedExtensions().first?.grantedPermissions
            == ["activeTab", "alarms", "storage", "tabs"])
        let personalContext = try #require(personal.extensions?.controller.extensionContexts.first)
        #expect(personalContext.currentPermissions.contains(.tabs))
        #expect(!personalContext.currentPermissions.contains(.cookies))
    }

    @Test func aNewManifestVersionReloadsUnderTheSameIdentifierAndAsksOnlyForWhatIsNew() async throws {
        let place = try Place()
        defer { place.clean() }
        let folder = try place.extensionFolder(key: nil)
        let profile = try ExtensionHostTests.profile()
        let library = place.library()
        await library.attach(try #require(profile.extensions), profile: profile.id)
        library.permissionPrompt = { _ in Issue.record("nothing new to ask"); return false }
        let installed = try #require(try await library.install(from: folder) { _ in true })
        let host = try #require(profile.extensions)
        let before = try #require(host.controller.extensionContexts.first)

        await library.checkForUpdates()
        #expect(host.controller.extensionContexts.first === before)

        try place.writeManifest(in: folder, version: "1.2.4", permissions: ["storage", "activeTab", "alarms", "tabs"], key: nil)
        var asked: [ExtensionPermissionRequest] = []
        library.permissionPrompt = { asked.append($0); return true }
        await library.checkForUpdates()

        #expect(asked.map(\.moment) == [.update])
        #expect(asked.first?.permissions == ["tabs"])
        #expect(asked.first?.matchPatterns == [])
        #expect(library.installed.first?.id == installed.id)
        #expect(library.installed.first?.version == "1.2.4")
        #expect(library.installed.first?.grantedPermissions == ["activeTab", "alarms", "storage", "tabs"])
        #expect(host.loadedExtensions.map(\.identifier) == [installed.id])
        #expect(host.loadedExtensions.map(\.version) == ["1.2.4"])
        #expect(host.controller.extensionContexts.first !== before)
        #expect(try AppDatabase(file: place.databaseFile).installedExtensions().first?.version == "1.2.4")
    }

    @Test func aCancelledUpdateRunsWithWhatWasAllowedAndIsAskedAgainOnlyFromThePane() async throws {
        let place = try Place()
        defer { place.clean() }
        let folder = try place.extensionFolder(key: nil)
        let profile = try ExtensionHostTests.profile()
        let library = place.library()
        await library.attach(try #require(profile.extensions), profile: profile.id)
        let installed = try #require(try await library.install(from: folder) { _ in true })
        let host = try #require(profile.extensions)

        try place.writeManifest(in: folder, version: "1.2.4", permissions: ["storage", "activeTab", "alarms", "tabs"], key: nil)
        var asked = 0
        library.permissionPrompt = { _ in asked += 1; return false }
        await library.checkForUpdates()

        #expect(asked == 1)
        #expect(library.installed.first?.version == "1.2.4")
        #expect(library.installed.first?.grantedPermissions == ["activeTab", "alarms", "storage"])
        #expect(library.statuses[installed.id]?.pendingRequest?.permissions == ["tabs"])
        #expect(host.loadedExtensions.map(\.version) == ["1.2.4"])
        let context = try #require(host.controller.extensionContexts.first)
        #expect(!context.currentPermissions.contains(.tabs))

        // The next activation does not ask again.
        await library.checkForUpdates()
        #expect(asked == 1)

        // After a relaunch the pane still shows what is not allowed.
        let relaunched = place.library()
        try await waitUntil("the relaunched library read what is not allowed") {
            relaunched.statuses[installed.id]?.pendingRequest != nil
        }
        #expect(relaunched.statuses[installed.id]?.pendingRequest?.permissions == ["tabs"])

        library.permissionPrompt = { _ in asked += 1; return true }
        await library.allowPending(installed.id)

        #expect(asked == 2)
        #expect(library.statuses[installed.id]?.pendingRequest == nil)
        #expect(library.installed.first?.grantedPermissions == ["activeTab", "alarms", "storage", "tabs"])
        #expect(try AppDatabase(file: place.databaseFile).installedExtensions().first?.grantedPermissions
            == ["activeTab", "alarms", "storage", "tabs"])
        #expect(context.currentPermissions.contains(.tabs))
    }

    @Test func aFolderThatNowHoldsAnotherExtensionStopsItUntilItIsRightAgain() async throws {
        let place = try Place()
        defer { place.clean() }
        let folder = try place.extensionFolder()
        let profile = try ExtensionHostTests.profile()
        let library = place.library()
        await library.attach(try #require(profile.extensions), profile: profile.id)
        try await library.install(from: folder) { _ in true }
        let host = try #require(profile.extensions)
        library.permissionPrompt = { _ in Issue.record("another extension is never asked about"); return false }

        try place.writeManifest(in: folder, version: "9.0.0", permissions: ["storage", "cookies"], key: "b3RoZXIta2V5",
                                name: "Stranger")
        await library.checkForUpdates()

        #expect(library.statuses[Self.fixtureID]?.availability == .differentExtension)
        #expect(host.loadedExtensions.isEmpty)
        #expect(library.installed.first?.displayName == "Safira fixture")
        #expect(library.installed.first?.version == "1.2.3")
        #expect(library.installed.first?.grantedPermissions == ["activeTab", "alarms", "storage"])
        #expect(try AppDatabase(file: place.databaseFile).installedExtensions().first?.version == "1.2.3")

        // A relaunch does not load it either.
        let later = try ExtensionHostTests.profile()
        let relaunched = place.library()
        await relaunched.attach(try #require(later.extensions), profile: later.id)
        #expect(relaunched.statuses[Self.fixtureID]?.availability == .differentExtension)
        #expect(try #require(later.extensions).loadedExtensions.isEmpty)
        // The row still words what was allowed: the stored grants reach every website.
        try await waitUntil("the relaunched library read its details") {
            relaunched.statuses[Self.fixtureID]?.hasAccessToAllHosts == true
        }

        // The extension is back in its folder, at the same version: it runs again under its identifier.
        try place.writeManifest(in: folder, version: "1.2.3", permissions: ["storage", "activeTab", "alarms"],
                                key: "c2FmaXJhLXRlc3Qta2V5")
        await library.checkForUpdates()

        #expect(library.statuses[Self.fixtureID]?.availability == .available)
        #expect(host.loadedExtensions.map(\.identifier) == [Self.fixtureID])
    }

    @Test func aStaleBookmarkIsMadeAgainAndAFolderThatIsGoneCanBeLocated() async throws {
        let place = try Place()
        defer { place.clean() }
        let folder = try place.extensionFolder()
        let bookmarks = FakeBookmarks()
        let library = place.library(bookmarks: bookmarks)
        try await library.install(from: folder) { _ in true }
        #expect(library.installed.first?.source == .folder(bookmark: FakeBookmarks.data(folder, generation: 1)))

        // The folder was replaced in place, as an app update does: the bookmark still finds it but is stale.
        bookmarks.staleOnce = true
        let profile = try ExtensionHostTests.profile()
        let relaunched = place.library(bookmarks: bookmarks)
        await relaunched.attach(try #require(profile.extensions), profile: profile.id)
        #expect(relaunched.installed.first?.source == .folder(bookmark: FakeBookmarks.data(folder, generation: 2)))
        #expect(try AppDatabase(file: place.databaseFile).installedExtensions().first?.source
            == .folder(bookmark: FakeBookmarks.data(folder, generation: 2)))
        #expect(try #require(profile.extensions).loadedExtensions.map(\.identifier) == [Self.fixtureID])

        // The folder is gone: the row says so, and Locate points the extension at its new place.
        let moved = place.root.appending(path: "Moved", directoryHint: .isDirectory)
        try FileManager.default.moveItem(at: folder, to: moved)
        let other = try ExtensionHostTests.profile()
        let again = place.library(bookmarks: bookmarks)
        await again.attach(try #require(other.extensions), profile: other.id)
        #expect(again.statuses[Self.fixtureID]?.availability == .missing)
        #expect(try #require(other.extensions).loadedExtensions.isEmpty)

        let stranger = try place.extensionFolder(key: "b3RoZXIta2V5", name: "Stranger")
        await #expect(throws: ExtensionInstallError.differentExtension(name: "Safira fixture")) {
            try await again.locate(Self.fixtureID, at: stranger)
        }
        try await again.locate(Self.fixtureID, at: moved)

        #expect(again.statuses[Self.fixtureID]?.availability == .available)
        #expect(try #require(other.extensions).loadedExtensions.map(\.identifier) == [Self.fixtureID])
        #expect(try AppDatabase(file: place.databaseFile).installedExtensions().first?.source
            == .folder(bookmark: FakeBookmarks.data(moved, generation: 3)))
    }

    @Test func anythingButAFolderZipOrCRXIsRefusedWithItsName() async throws {
        let place = try Place()
        defer { place.clean() }
        let text = place.root.appending(path: "readme.txt")
        try Data("not an extension".utf8).write(to: text)
        let library = place.library()

        await #expect(throws: ExtensionInstallError.unsupportedFile(name: "readme.txt")) {
            try await library.install(from: text) { _ in true }
        }
        #expect(library.installed.isEmpty)
        #expect(ExtensionInstallError.unsupportedFile(name: "readme.txt").errorDescription
            == "“readme.txt” is not an extension. Choose a folder that holds a manifest.json file, or a .zip or .crx file.")
    }

    /// A non-persistent controller keeps extension storage in memory and lists no data records, so this test uses a
    /// controller with a persistent identifier of its own, new for the test (never a Profile's), over a non-persistent
    /// website data store. What the service worker stores is `storage.local`, never a `CryptoKey`, so the keychain is
    /// not reached. WebKit lists a record for every extension it knows, empty or not: what counts is its size.
    @Test(arguments: [true, false])
    func removeDeletesWhatTheExtensionStored(throughItsOwnController: Bool) async throws {
        let place = try Place()
        defer { place.clean() }
        let folder = try place.extensionFolder()
        let profile = ProfileID(rawValue: UUID())
        let controller = Self.controller(identifiedBy: profile)
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: folder))
        context.uniqueIdentifier = Self.fixtureID
        context.setPermissionStatus(.grantedExplicitly, for: .storage)
        try controller.load(context)
        let error: (any Error)? = await withCheckedContinuation { done in
            context.loadBackgroundContent { done.resume(returning: $0) }
        }
        #expect(error == nil)
        try await waitUntilAsync("the service worker stored its mark") {
            await Self.storedBytes(Self.fixtureID, in: controller) > 0
        }

        // Remove unloads first, then deletes: from the Profile's own controller when the Profile is loaded, else
        // through a new controller of the same identifier.
        if throughItsOwnController {
            await ExtensionHost.removeData(of: "another-extension", from: controller)
            #expect(await Self.storedBytes(Self.fixtureID, in: controller) > 0)
            try controller.unload(context)
            await ExtensionHost.removeData(of: Self.fixtureID, from: controller)
        } else {
            try controller.unload(context)
            await ExtensionHost.removeData(of: Self.fixtureID, inProfile: profile)
        }

        #expect(await Self.storedBytes(Self.fixtureID, in: controller) == 0)
        #expect(await Self.storedBytes(Self.fixtureID, in: Self.controller(identifiedBy: profile)) == 0)
    }

    // MARK: Helpers

    /// The identifiers of the extensions with stored data in a host's controller.
    static func storedBytes(_ extensionID: String, in controller: WKWebExtensionController) async -> Int {
        await controller.dataRecords(ofTypes: [.local, .session, .synchronized])
            .filter { $0.uniqueIdentifier == extensionID }
            .reduce(0) { $0 + $1.totalSizeInBytes }
    }

    static func controller(identifiedBy profile: ProfileID) -> WKWebExtensionController {
        let configuration = WKWebExtensionController.Configuration(identifier: profile.rawValue)
        configuration.defaultWebsiteDataStore = .nonPersistent()
        return WKWebExtensionController(configuration: configuration)
    }

    /// A temporary folder for one test: the list's database, the copies, and the extensions written by the test.
    struct Place {
        let root = FileManager.default.temporaryDirectory.appending(path: "safira-library-\(UUID().uuidString)",
                                                                    directoryHint: .isDirectory)
        var databaseFile: URL { root.appending(path: "app.sqlite") }
        var copiesDirectory: URL { root.appending(path: "Extensions", directoryHint: .isDirectory) }

        init() throws {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        @MainActor
        func library(bookmarks: any ExtensionFolderBookmarks = FakeBookmarks()) -> ExtensionLibrary {
            ExtensionLibrary(database: try? AppDatabase(file: databaseFile), directory: copiesDirectory,
                             bookmarks: bookmarks, storage: .inMemory) { message, error in
                Issue.record("\(message): \(error)")
            }
        }

        func copies() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: copiesDirectory.path(percentEncoded: false))) ?? []).sorted()
        }

        /// The fixture extension: a content script that marks pages, and a service worker that stores a value.
        func extensionFolder(key: String? = "c2FmaXJhLXRlc3Qta2V5", name: String = "Safira fixture") throws -> URL {
            let folder = root.appending(path: "\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeManifest(in: folder, version: "1.2.3", permissions: ["storage", "activeTab", "alarms"], key: key,
                              name: name)
            try Data("chrome.storage.local.set({ installed: true });".utf8).write(to: folder.appending(path: "background.js"))
            try Data("document.documentElement.dataset.isolated = 'isolated';".utf8)
                .write(to: folder.appending(path: "isolated.js"))
            return folder
        }

        func writeManifest(in folder: URL, version: String, permissions: [String], key: String?,
                           name: String = "Safira fixture") throws {
            var manifest: [String: Any] = [
                "manifest_version": 3,
                "name": name,
                "description": "Marks the pages it runs in.",
                "version": version,
                "permissions": permissions,
                "background": ["service_worker": "background.js"],
                "content_scripts": [[
                    "matches": ["https://*/*", "http://localhost/*", "http://127.0.0.1/*"],
                    "js": ["isolated.js"], "run_at": "document_start",
                ]],
            ]
            if let key { manifest["key"] = key }
            try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
                .write(to: folder.appending(path: "manifest.json"))
        }

        /// A ZIP of the folder's contents, made by `ditto`, with `manifest.json` at its root.
        func zip(of folder: URL) throws -> URL {
            let zip = root.appending(path: "\(folder.lastPathComponent).zip")
            let ditto = Process()
            ditto.executableURL = URL(filePath: "/usr/bin/ditto")
            ditto.arguments = ["-c", "-k", folder.path(percentEncoded: false), zip.path(percentEncoded: false)]
            try ditto.run()
            ditto.waitUntilExit()
            try #require(ditto.terminationStatus == 0)
            return zip
        }

        func clean() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}

/// Bookmarks that hold the folder's path and a generation, so a test sees when one is made again; `staleOnce` makes
/// the next resolution report a stale bookmark, as macOS does for a folder replaced in place.
final class FakeBookmarks: ExtensionFolderBookmarks, @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    var staleOnce = false

    static func data(_ folder: URL, generation: Int) -> Data {
        Data("\(generation)|\(folder.absoluteURL.standardizedFileURL.path(percentEncoded: false))".utf8)
    }

    func bookmark(for folder: URL) throws -> Data {
        lock.withLock {
            generation += 1
            return Self.data(folder, generation: generation)
        }
    }

    func resolve(_ bookmark: Data) throws -> ResolvedFolder {
        let text = String(decoding: bookmark, as: UTF8.self)
        guard let bar = text.firstIndex(of: "|") else { throw CocoaError(.fileReadCorruptFile) }
        let stale = lock.withLock {
            defer { staleOnce = false }
            return staleOnce
        }
        return ResolvedFolder(url: URL(filePath: String(text[text.index(after: bar)...]), directoryHint: .isDirectory),
                              isStale: stale)
    }

    func startAccessing(_ folder: URL) -> Bool { true }
    func stopAccessing(_ folder: URL) {}
}
