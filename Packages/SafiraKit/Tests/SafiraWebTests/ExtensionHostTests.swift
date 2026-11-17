// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Network
import SafiraCore
import SafiraStore
@testable import SafiraWeb
import Testing
import WebKit

/// Web extensions per Profile, on real WebKit. Every Profile here is `.inMemory`: its data store and its extensions'
/// state are non-persistent, and no extension stores a `CryptoKey`, so nothing reaches the disk or the keychain.
@MainActor
@Suite(.serialized, .oneWebKitTestAtATime) struct ExtensionHostTests {
    /// Verrou's manifest `key` (a public key, published in its repository).
    static let verrouKey = """
        MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAyQmZR1Ax8wCjoyiOOneDiobQiOu44TbZ5bBnOdjyweU+IwNo6RgeaM3AQ3wtHjF560eI/\
        MkDuHWo4NAqKrI+/2I/ly1riSv+t/zCZzCCz65vnk+LTikgO6XRSCNm0inmBsA6u59stnckqu3cOA+8KG/L7HEpyuzJoFFTjgGwIo6dmuXGi76KH3Nyrx\
        e/kRixbiIBb22rCKVMTiCt/FxRTR4/F7DAa3fJo87KaW6jRUw6XkxcsIt8HG2mIGXH7g+VLr05K62ll6nFdHoJhGnDFmVXaHhwVEmpq46Z6L/tFMSm1661u\
        7CZYEYhhbJYIHcbd2mbWcJGVj2PubeWZ8aHswIDAQAB
        """

    @Test func theIdentifierComesFromTheManifestKeyAsChromeDerivesIt() {
        #expect(ExtensionIdentity.identifier(forManifestKey: Self.verrouKey) == "pmdlgnpbjfdnmpeadbecmgfoojmocibg")
        #expect(ExtensionIdentity.identifier(forManifestKey: "c2FmaXJhLXRlc3Qta2V5") == "pfikphmpnbnmihdgfbljkjgfnamcpjme")
    }

    @Test func anExtensionWithoutAKeyGetsANewIdentifierEachTime() {
        #expect(ExtensionIdentity.identifier(forManifestKey: nil) == nil)
        #expect(ExtensionIdentity.identifier(forManifestKey: "") == nil)
        let first = ExtensionIdentity.identifier(forManifest: ["name": "No key"])
        let second = ExtensionIdentity.identifier(forManifest: ["name": "No key"])
        #expect(first != second)
    }

    @Test func aPrivateWindowHasNoExtensions() {
        let context = ProfileWebContext(privateWindowOf: ProfileID(rawValue: UUID()))
        #expect(context.extensions == nil)
        #expect(context.makeConfiguration().webExtensionController == nil)
    }

    @Test func theControllerUsesTheProfilesOwnDataStore() throws {
        let profile = try Self.profile()
        let host = try #require(profile.extensions)
        #expect(host.controller.configuration.defaultWebsiteDataStore === profile.web.dataStore)
        #expect(profile.web.makeConfiguration().webExtensionController === host.controller)
        #expect(!host.controller.configuration.isPersistent)
    }

    @Test func aLoadedExtensionInjectsItsContentScriptsInBothWorldsAndOnlyInItsProfile() async throws {
        let folder = try Self.fixtureExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = try await AnyHostServer.start()
        let work = try Self.profile()
        let personal = try Self.profile()

        let loaded = try await #require(work.extensions).loadUnpacked(at: folder)
        #expect(loaded == LoadedExtension(identifier: "pfikphmpnbnmihdgfbljkjgfnamcpjme", displayName: "Safira fixture",
                                          version: "1.2.3", errors: []))
        try await Self.loadBackgroundContent(of: work)

        let workTab = work.session.openExternalLink(server.url(host: "127.0.0.1"))
        let personalTab = personal.session.openExternalLink(server.url(host: "127.0.0.1"))
        try await Self.waitUntilLoaded(work, workTab)
        try await Self.waitUntilLoaded(personal, personalTab)
        try await waitUntilAsync("the fixture's content scripts ran in the Work Profile's page") {
            await Self.evaluate("`${document.documentElement.dataset.isolated} ${window.__fixtureMain}`", in: work, workTab)
                == "isolated main"
        }
        // The isolated script's DOM mark is visible to the page; its globals are not.
        #expect(await Self.evaluate("String(window.__fixtureIsolated)", in: work, workTab) == "undefined")

        #expect(try #require(personal.extensions).loadedExtensions == [])
        #expect(await Self.evaluate("`${document.documentElement.dataset.isolated} ${window.__fixtureMain}`",
                                    in: personal, personalTab) == "undefined undefined")
        server.stop()
    }

    /// `Bundle.resourceURL`, and what is appended to it, is relative to the bundle; WebKit used to kill the app on it.
    @Test func aFolderGivenRelativeToABaseLoads() async throws {
        let folder = try Self.fixtureExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let relative = URL(filePath: folder.lastPathComponent, directoryHint: .isDirectory,
                           relativeTo: folder.deletingLastPathComponent())
        #expect(relative.baseURL != nil)
        let profile = try Self.profile()

        let loaded = try await #require(profile.extensions).loadUnpacked(at: relative)
        #expect(loaded.displayName == "Safira fixture")
        #expect(loaded.errors == [])
    }

    @Test func anAddressThatIsNotAFolderOnDiskIsRefused() async throws {
        let profile = try Self.profile()
        let host = try #require(profile.extensions)
        await #expect(throws: ExtensionFolderUnreadable.self) {
            try await host.loadUnpacked(at: URL(string: "https://example.com/extension/")!)
        }
        #expect(host.loadedExtensions == [])
    }

    /// What `sender.url` and `tabs.query` report is the committed page, not a navigation that has only started.
    @Test func aTabReportsItsCommittedAddressWhileANavigationIsPending() async throws {
        let folder = try Self.fixtureExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = try await AnyHostServer.start()
        let silent = try await SilentServer.start()
        let profile = try Self.profile()
        let host = try #require(profile.extensions)
        try await host.loadUnpacked(at: folder)
        let context = try #require(host.controller.extensionContexts.first)

        let committed = server.url(host: "127.0.0.1")
        let id = profile.session.openExternalLink(committed)
        try await Self.waitUntilLoaded(profile, id)
        let tab = try #require(host.openTabs.first { $0.id == id })
        #expect(tab.url(for: context) == committed)

        let pending = URL(string: "http://127.0.0.1:\(silent.port)/never")!
        let webView = try #require(profile.web.webView(for: id))
        webView.load(URLRequest(url: pending))
        try await waitUntil("WebKit shows the pending address") { webView.url == pending }
        #expect(tab.url(for: context) == committed)
        server.stop()
        silent.stop()
    }

    @Test func theControllerHearsTabsOpenCloseAndBecomeActive() async throws {
        let folder = try Self.fixtureExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = try Self.profile()
        let host = try #require(profile.extensions)
        try await host.loadUnpacked(at: folder)
        let context = try #require(host.controller.extensionContexts.first)

        let first = profile.session.openExternalLink(URL(string: "about:blank")!)
        let second = profile.session.openExternalLink(URL(string: "about:blank")!)
        try await waitUntil("both pages are open to the extension") { context.openTabs.count == 2 }
        try await waitUntil("the second Tab is the active one") { host.activeTab?.id == second }
        #expect(host.openTabs.map(\.id) == [first, second])
        let window = try #require(context.focusedWindow)
        #expect(window.tabs?(for: context).count == 2)

        profile.session.select(first)
        try await waitUntil("selecting the first Tab activates it") { host.activeTab?.id == first }
        #expect((window.activeTab?(for: context) as? ExtensionTab)?.id == first)

        profile.session.close(second)
        try await waitUntil("the closed Tab is gone for the extension") { context.openTabs.count == 1 }
        #expect(host.openTabs.map(\.id) == [first])
    }

    /// Verrou, the first extension Safira runs, read from a copy of its folder. It needs Verrou installed (or
    /// `SAFIRA_VERROU_EXTENSION` naming its extension folder), so it does not run in CI.
    @Test(.enabled(if: ExtensionHostTests.verrouFolder != nil, "needs Verrou's extension folder"))
    func verrouLoadsWithNoErrorAndItsPasskeyScriptReachesTheServedPage() async throws {
        let original = try #require(Self.verrouFolder)
        let copy = FileManager.default.temporaryDirectory.appending(path: "safira-verrou-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: original, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let server = try await AnyHostServer.start()
        let work = try Self.profile()
        let personal = try Self.profile()

        let loaded = try await #require(work.extensions).loadUnpacked(at: copy)
        #expect(loaded.identifier == "pmdlgnpbjfdnmpeadbecmgfoojmocibg")
        #expect(loaded.displayName == "Verrou")
        #expect(loaded.errors == [])
        try await Self.loadBackgroundContent(of: work)

        // Verrou's MAIN-world script (passkey-page.js) runs on https pages and on localhost, and wraps
        // navigator.credentials.get, which then no longer reads as native code.
        let wrapped = "String(!navigator.credentials.get.toString().includes('[native code]'))"
        let workTab = work.session.openExternalLink(server.url(host: "localhost"))
        let personalTab = personal.session.openExternalLink(server.url(host: "localhost"))
        try await Self.waitUntilLoaded(work, workTab)
        try await Self.waitUntilLoaded(personal, personalTab)
        try await waitUntilAsync("Verrou's passkey script wrapped navigator.credentials.get") {
            await Self.evaluate(wrapped, in: work, workTab) == "true"
        }
        #expect(await Self.evaluate(wrapped, in: personal, personalTab) == "false")
        #expect(try #require(work.extensions).loadedExtensions.map(\.identifier) == ["pmdlgnpbjfdnmpeadbecmgfoojmocibg"])
        #expect(try #require(personal.extensions).loadedExtensions == [])
        let errors = try #require(work.extensions?.controller.extensionContexts.first).errors
        #expect(errors.map(\.localizedDescription) == [])
        server.stop()
    }

    // MARK: Helpers

    nonisolated static var verrouFolder: URL? {
        let named = ProcessInfo.processInfo.environment["SAFIRA_VERROU_EXTENSION"]
        let path = named ?? "/Applications/Verrou.app/Contents/Resources/extension"
        let folder = URL(filePath: path, directoryHint: .isDirectory)
        return FileManager.default.fileExists(atPath: folder.appending(path: "manifest.json").path(percentEncoded: false))
            ? folder : nil
    }

    static func profile() throws -> ProfileContext {
        ProfileContext(id: ProfileID(rawValue: UUID()), database: try .inMemory(firstSpaceName: "Home"),
                       siteIconsDirectory: nil, diagnostics: nil, storage: .inMemory) { message, error in
            Issue.record("\(message): \(error)")
        }
    }

    static func loadBackgroundContent(of profile: ProfileContext) async throws {
        let context = try #require(profile.extensions?.controller.extensionContexts.first)
        let error: (any Error)? = await withCheckedContinuation { done in
            context.loadBackgroundContent { done.resume(returning: $0) }
        }
        #expect(error == nil, "the service worker did not start: \(String(describing: error))")
    }

    static func waitUntilLoaded(_ profile: ProfileContext, _ tab: TabID) async throws {
        try await waitUntil("the page loaded") {
            guard let webView = profile.web.webView(for: tab) else { return false }
            return webView.url != nil && !webView.isLoading
        }
    }

    static func evaluate(_ script: String, in profile: ProfileContext, _ tab: TabID) async -> String? {
        guard let webView = profile.web.webView(for: tab) else { return nil }
        return try? await webView.callAsyncJavaScript("return \(script)", contentWorld: .page) as? String
    }

    /// A Manifest V3 extension with the shapes Verrou uses: a `key`, a module service worker that imports a file, and
    /// content scripts in the isolated and the MAIN world, written into a new temporary folder.
    static func fixtureExtension() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "safira-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = [
            "manifest.json": """
                {
                  "manifest_version": 3,
                  "name": "Safira fixture",
                  "description": "Marks the pages it runs in.",
                  "version": "1.2.3",
                  "key": "c2FmaXJhLXRlc3Qta2V5",
                  "permissions": ["storage", "activeTab", "alarms"],
                  "background": { "service_worker": "background.js", "type": "module" },
                  "content_scripts": [
                    { "matches": ["https://*/*", "http://localhost/*", "http://127.0.0.1/*"], "js": ["isolated.js"],
                      "run_at": "document_start" },
                    { "matches": ["https://*/*", "http://localhost/*", "http://127.0.0.1/*"], "js": ["main.js"],
                      "world": "MAIN", "run_at": "document_start" }
                  ]
                }
                """,
            "background.js": "import { started } from './started.js'; globalThis.started = started;",
            "started.js": "export const started = true;",
            "isolated.js": "window.__fixtureIsolated = 1; document.documentElement.dataset.isolated = 'isolated';",
            "main.js": "window.__fixtureMain = 'main';",
        ]
        for (name, text) in files {
            try Data(text.utf8).write(to: folder.appending(path: name))
        }
        return folder
    }
}

extension ExtensionHost {
    /// Loads an unpacked extension as the extension library does once the user allowed everything it asks for, under
    /// the identifier its manifest `key` gives (a new one without a key).
    @discardableResult
    func loadUnpacked(at folder: URL) async throws -> LoadedExtension {
        guard folder.isFileURL else {
            let nothing = InstalledExtension(id: "none", source: .folder(bookmark: Data()), displayName: "", version: "",
                                             grantedPermissions: [], grantedMatchPatterns: [], installedAt: Date())
            return try await load(nothing, from: folder)
        }
        let webExtension = try await WKWebExtension(resourceBaseURL: folder.absoluteURL.standardizedFileURL)
        let installed = InstalledExtension(id: ExtensionIdentity.identifier(forManifest: webExtension.manifest),
                                           source: .folder(bookmark: Data()), displayName: webExtension.displayName ?? "",
                                           version: webExtension.version ?? "",
                                           grantedPermissions: webExtension.requestedPermissions.map(\.rawValue),
                                           grantedMatchPatterns: webExtension.allRequestedMatchPatterns.map(\.string),
                                           installedAt: Date())
        return try await load(installed, from: folder)
    }
}

/// A loopback HTTP server that answers every GET with a blank page, whatever the Host header: Verrou's MAIN-world
/// script matches `http://localhost/*`, which the other test servers, bound to the `127.0.0.1` host, refuse.
final class AnyHostServer: @unchecked Sendable {
    private let listener: NWListener
    let port: UInt16

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func start() async throws -> AnyHostServer {
        signal(SIGPIPE, SIG_IGN)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                guard let data, String(decoding: data, as: UTF8.self).hasPrefix("GET ") else { return connection.cancel() }
                let body = "<!doctype html><title>extension test</title><body>extension test</body>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\n"
                    + "Cache-Control: no-store\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), contentContext: .finalMessage, isComplete: true,
                                completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let ready = AsyncThrowingStream<UInt16, any Error> { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: continuation.yield(listener.port?.rawValue ?? 0); continuation.finish()
                case .failed(let error): continuation.finish(throwing: error)
                default: break
                }
            }
        }
        listener.start(queue: .global())
        var iterator = ready.makeAsyncIterator()
        return AnyHostServer(listener: listener, port: try await iterator.next() ?? 0)
    }

    func url(host: String) -> URL {
        URL(string: "http://\(host):\(port)/")!
    }

    func stop() {
        listener.cancel()
    }
}

/// Accepts connections and never answers, so that a navigation to it stays pending.
final class SilentServer: @unchecked Sendable {
    private let listener: NWListener
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    let port: UInt16

    private init(listener: NWListener, port: UInt16) {
        self.listener = listener
        self.port = port
    }

    static func start() async throws -> SilentServer {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = AsyncThrowingStream<UInt16, any Error> { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: continuation.yield(listener.port?.rawValue ?? 0); continuation.finish()
                case .failed(let error): continuation.finish(throwing: error)
                default: break
                }
            }
        }
        let held = Held()
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            held.server?.keep(connection)
        }
        listener.start(queue: .global())
        var iterator = ready.makeAsyncIterator()
        let server = SilentServer(listener: listener, port: try await iterator.next() ?? 0)
        held.server = server
        return server
    }

    private final class Held: @unchecked Sendable {
        weak var server: SilentServer?
    }

    private func keep(_ connection: NWConnection) {
        lock.withLock { connections.append(connection) }
    }

    func stop() {
        listener.cancel()
        lock.withLock { connections }.forEach { $0.cancel() }
    }
}
