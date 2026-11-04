// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CoreGraphics
import Foundation
import Network
import SafiraCore
import SafiraSession
import SafiraWeb
import Testing
import WebKit

/// A loopback origin for the isolation suite: `/` is a blank page, `/sw.js` a service worker script, and `/cookie`
/// sets an HttpOnly cookie from the server.
final class StorageServer: @unchecked Sendable {
    private let listener: NWListener
    let port: UInt16

    init() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
                let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                let (type, body, extra) = switch path {
                case "/sw.js": ("application/javascript", "self.addEventListener('fetch', () => {});", "")
                case "/cookie": ("text/html", "<!doctype html><title>cookie</title>",
                                 "Set-Cookie: server=A; Path=/; HttpOnly\r\n")
                default: ("text/html", "<!doctype html><title>storage</title>", "")
                }
                let response = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(body.utf8.count)\r\n"
                    + "Cache-Control: no-store\r\n\(extra)Connection: close\r\n\r\n\(body)"
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
        self.listener = listener
        self.port = try await iterator.next() ?? 0
    }

    func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    deinit { listener.cancel() }
}

/// What one page of an origin can read of each kind of website data.
struct StoredData: Decodable, Equatable {
    var cookie: String
    var local: String?
    var session: String?
    var indexedDB: [String]
    var serviceWorkers: Int
    var caches: [String]

    static let none = StoredData(cookie: "", local: nil, session: nil, indexedDB: [], serviceWorkers: 0, caches: [])
}

let writeEverything = """
    document.cookie = "script=A; path=/";
    localStorage.setItem("key", "A");
    sessionStorage.setItem("key", "A");
    await new Promise((resolve, reject) => {
        const request = indexedDB.open("isolation", 1);
        request.onupgradeneeded = () => request.result.createObjectStore("store");
        request.onerror = () => reject(request.error);
        request.onsuccess = () => {
            const transaction = request.result.transaction("store", "readwrite");
            transaction.objectStore("store").put("A", "key");
            transaction.oncomplete = () => { request.result.close(); resolve(); };
            transaction.onerror = () => reject(transaction.error);
        };
    });
    await navigator.serviceWorker.register("/sw.js");
    await navigator.serviceWorker.ready;
    const cache = await caches.open("isolation");
    await cache.put("/cached", new Response("A"));
    return "written";
    """

let readEverything = """
    const databases = await indexedDB.databases();
    const workers = await navigator.serviceWorker.getRegistrations();
    return JSON.stringify({
        cookie: document.cookie,
        local: localStorage.getItem("key"),
        session: sessionStorage.getItem("key"),
        indexedDB: databases.map(database => database.name).sort(),
        serviceWorkers: workers.length,
        caches: (await caches.keys()).sort(),
    });
    """

/// Proves that a Profile's website data is invisible from another Profile, by writing every kind of data in one
/// Profile's data store and reading the same origin from another's (docs/architecture-v1.md §9.2). Real WebKit: the
/// suite needs a graphical session, and fails without one instead of skipping.
@MainActor
@Suite(.serialized) struct IsolationTests {
    @Test func aGraphicalSessionIsAvailable() {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        #expect(session != nil, "the isolation suite needs a logged-in graphical session; it does not skip without one")
        #expect(session?[kCGSessionOnConsoleKey as String] as? Bool == true,
                "the isolation suite needs the graphical session on the console")
    }

    @Test func eachProfileGetsTheDataStoreNamedByItsOwnUUID() async throws {
        let work = try #require(ProfileID(uuidString: "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A"))
        let personal = try #require(ProfileID(uuidString: "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F"))

        do {
            let workContext = ProfileWebContext(profileID: work)
            let personalContext = ProfileWebContext(profileID: personal)

            #expect(workContext.makeConfiguration().websiteDataStore.identifier?.uuidString
                == "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A")
            #expect(personalContext.makeConfiguration().websiteDataStore.identifier?.uuidString
                == "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F")
            #expect(workContext.makeConfiguration().websiteDataStore === workContext.dataStore)
        }

        await removeDataStoreWhenReleased(work)
        await removeDataStoreWhenReleased(personal)
    }

    @Test func everyKindOfWebsiteDataWrittenInOneProfileIsInvisibleInAnother() async throws {
        let server = try await StorageServer()
        let work = ProfileID(rawValue: UUID())
        let personal = ProfileID(rawValue: UUID())
        do {
            let workContext = ProfileWebContext(profileID: work)
            let personalContext = ProfileWebContext(profileID: personal)
            let writer = try await page(at: server.url("/cookie"), in: workContext, tab: TabID())
            #expect(try await run(writeEverything, in: writer) == "written")

            let otherTabOfWork = try await page(at: server.url("/"), in: workContext, tab: TabID())
            let workSees = try await read(in: otherTabOfWork)
            #expect(workSees == StoredData(cookie: "script=A", local: "A", session: nil, indexedDB: ["isolation"],
                                           serviceWorkers: 1, caches: ["isolation"]))
            #expect(try await read(in: writer).session == "A")
            #expect(await cookieNames(workContext) == ["script", "server"])

            let personalPage = try await page(at: server.url("/"), in: personalContext, tab: TabID())
            #expect(try await read(in: personalPage) == .none)
            #expect(await cookieNames(personalContext) == [])
            #expect(await personalContext.dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
                .flatMap(\.dataTypes).filter { $0 != WKWebsiteDataTypeMemoryCache }.isEmpty)

            for page in [writer, otherTabOfWork, personalPage] { page.close() }
        }
        await removeDataStoreWhenReleased(work)
        await removeDataStoreWhenReleased(personal)
    }

    @Test func dataPersistsForTheSameProfileIdentifierAndDoesNotExistForANewOne() async throws {
        let server = try await StorageServer()
        let profile = ProfileID(rawValue: UUID())
        let fresh = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let writer = try await page(at: server.url("/cookie"), in: context, tab: TabID())
            #expect(try await run(writeEverything, in: writer) == "written")
            writer.close()
        }
        do {
            let again = ProfileWebContext(profileID: profile)
            let reader = try await page(at: server.url("/"), in: again, tab: TabID())
            #expect(try await read(in: reader) == StoredData(cookie: "script=A", local: "A", session: nil,
                                                              indexedDB: ["isolation"], serviceWorkers: 1,
                                                              caches: ["isolation"]))
            #expect(await cookieNames(again) == ["script", "server"])
            reader.close()

            let newProfile = ProfileWebContext(profileID: fresh)
            let empty = try await page(at: server.url("/"), in: newProfile, tab: TabID())
            #expect(try await read(in: empty) == .none)
            #expect(await cookieNames(newProfile) == [])
            empty.close()
        }
        await removeDataStoreWhenReleased(profile)
        await removeDataStoreWhenReleased(fresh)
    }

    @Test func clearingAllTimeInOneProfileRemovesEveryKindOfItsWebsiteDataAndLeavesAnotherProfilesUntouched() async throws {
        let server = try await StorageServer()
        let work = ProfileID(rawValue: UUID())
        let personal = ProfileID(rawValue: UUID())
        let written = StoredData(cookie: "script=A", local: "A", session: nil, indexedDB: ["isolation"],
                                 serviceWorkers: 1, caches: ["isolation"])
        do {
            let workContext = ProfileWebContext(profileID: work)
            let personalContext = ProfileWebContext(profileID: personal)
            let workWriter = try await page(at: server.url("/cookie"), in: workContext, tab: TabID())
            let personalWriter = try await page(at: server.url("/cookie"), in: personalContext, tab: TabID())
            #expect(try await run(writeEverything, in: workWriter) == "written")
            #expect(try await run(writeEverything, in: personalWriter) == "written")
            #expect(await cookieNames(workContext) == ["script", "server"])
            #expect(await cookieNames(personalContext) == ["script", "server"])

            await workContext.clearWebsiteData(since: ClearRange.allTime.start())

            let workReader = try await page(at: server.url("/"), in: workContext, tab: TabID())
            let personalReader = try await page(at: server.url("/"), in: personalContext, tab: TabID())
            #expect(try await read(in: workReader) == .none)
            #expect(await cookieNames(workContext) == [])
            #expect(await workContext.dataStore.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
                .flatMap(\.dataTypes).filter { $0 != WKWebsiteDataTypeMemoryCache }.isEmpty)
            #expect(try await read(in: personalReader) == written)
            #expect(await cookieNames(personalContext) == ["script", "server"])
            for page in [workWriter, personalWriter, workReader, personalReader] { page.close() }
        }
        await removeDataStoreWhenReleased(work)
        await removeDataStoreWhenReleased(personal)
    }

    @Test func aPopupUsesTheDataStoreOfItsOpenersProfileAndNeverAnotherProfilesStore() async throws {
        let site = try await SignInSite()
        let work = try #require(ProfileID(uuidString: "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A"))
        let personal = try #require(ProfileID(uuidString: "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F"))
        do {
            let workContext = ProfileWebContext(profileID: work)
            let personalContext = ProfileWebContext(profileID: personal)
            let session = ProfileSession(profileID: work) { workContext.makePage(for: $0) }
            let personalSession = ProfileSession(profileID: personal) { personalContext.makePage(for: $0) }
            for (session, context) in [(session, workContext), (personalSession, personalContext)] {
                session.openCommandBar(for: .newTab)
                session.submitCommandBar(site.app("/app").absoluteString)
                let opener = try #require(session.selectedTabID.flatMap(context.webView(for:)))
                try await waitUntil("the opener loads") { opener.title == "app: signed out" }
            }
            let workOpener = try #require(session.selectedTabID.flatMap(workContext.webView(for:)))
            _ = try await workOpener.evaluateJavaScript("document.getElementById('hold').click()")
            try await waitUntil("the popup opens") { !session.popups.isEmpty }
            let popupID = try #require(session.popups.first?.id)
            let popup = try #require(workContext.webView(forPopup: popupID))
            try await waitUntil("the popup loads") { popup.title == "provider: waiting" && !popup.isLoading }

            #expect(popup.configuration.websiteDataStore === workContext.dataStore)
            #expect(popup.configuration.websiteDataStore.identifier?.uuidString == "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A")
            #expect(popup.configuration.websiteDataStore !== personalContext.dataStore)
            #expect(popup.configuration.websiteDataStore.identifier != personal.rawValue)
            #expect(await workContext.dataStore.httpCookieStore.allCookies().map(\.name) == ["idp_session"])
            #expect(await personalContext.dataStore.httpCookieStore.allCookies() == [])
            #expect(personalSession.popups.isEmpty)

            session.closeAllTabs()
            personalSession.closeAllTabs()
        }
        await removeDataStoreWhenReleased(work)
        await removeDataStoreWhenReleased(personal)
    }

    @Test func aRangeThatStartsAfterTheDataWasWrittenKeepsItAndOneThatStartsBeforeRemovesIt() async throws {
        let server = try await StorageServer()
        let profile = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let writer = try await page(at: server.url("/cookie"), in: context, tab: TabID())
            #expect(try await run(writeEverything, in: writer) == "written")

            try await Task.sleep(for: .seconds(2))
            await context.clearWebsiteData(since: Date())
            #expect(await cookieNames(context) == ["script", "server"])
            #expect(try await read(in: writer).local == "A")

            await context.clearWebsiteData(since: Date().addingTimeInterval(3_600))
            #expect(await cookieNames(context) == ["script", "server"])

            await context.clearWebsiteData(since: ClearRange.lastHour.start())
            #expect(await cookieNames(context) == [])
            let reader = try await page(at: server.url("/"), in: context, tab: TabID())
            #expect(try await read(in: reader) == .none)
            for page in [writer, reader] { page.close() }
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aPageOpenWhileItsProfileIsClearedKeepsRunningAndItsStoredDataIsGone() async throws {
        let server = try await StorageServer()
        let profile = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let open = try await page(at: server.url("/cookie"), in: context, tab: TabID())
            #expect(try await run(writeEverything, in: open) == "written")

            await context.clearWebsiteData(since: .distantPast)

            // No reload happened: the page is still the one that was loaded, and the data it can read is gone.
            #expect(open.webView.url == server.url("/cookie"))
            #expect(try await read(in: open) == .none)
            #expect(await cookieNames(context) == [])
            open.close()
        }
        await removeDataStoreWhenReleased(profile)
    }

    // MARK: Helpers

    private func page(at url: URL, in context: ProfileWebContext, tab: TabID) async throws -> WebKitPage {
        let page = context.makePage(for: tab)
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

    private func cookieNames(_ context: ProfileWebContext) async -> [String] {
        await context.dataStore.httpCookieStore.allCookies().map(\.name).sorted()
    }
}
