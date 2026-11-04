// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Network
import SafiraCore
import SafiraSession
import SafiraWeb
import Testing
import WebKit

/// Serves a few fixed pages on a loopback port, chosen by the path of the request line, whatever its method.
private final class PageServer: @unchecked Sendable {
    private static let pages = [
        "/plain": #"<title>Plain</title><p>nothing to hide</p>"#,
        "/plain2": #"<title>Plain 2</title><p>still nothing</p>"#,
        "/login": #"<title>Login</title><form><input name="user"><input type="password" name="secret"></form>"#,
        "/later": """
            <title>Later</title><div id="dialog"></div>
            <script>setTimeout(() => { document.getElementById("dialog").innerHTML = '<input type="password">' }, 200)</script>
            """,
        "/framed": #"<title>Framed</title><iframe src="/login"></iframe>"#,
        "/form": #"<title>Form</title><form method="post" action="/posted"><input name="q" value="typed"></form>"#,
        "/posted": #"<title>Posted</title><p>thanks</p>"#,
    ]

    let listener: NWListener
    let port: UInt16

    init() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let requestLine = data.flatMap { String(decoding: $0, as: UTF8.self).split(separator: "\r\n").first }
                let path = requestLine.map { String($0.split(separator: " ").dropFirst().first ?? "") } ?? ""
                let body = "<!doctype html><html><body>\(Self.pages[path] ?? "<title>Missing</title>")</body></html>"
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
        self.listener = listener
        self.port = try await iterator.next() ?? 0
    }

    func url(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    deinit { listener.cancel() }
}

/// Decision D1 and lazy restoration with real WebKit pages: what the session would write to disk, and how a saved
/// Tab comes back.
@MainActor
@Suite(.serialized) struct NavigationStateTests {
    private func makeSession(_ profile: ProfileID) -> (ProfileSession, ProfileWebContext) {
        let context = ProfileWebContext(profileID: profile)
        let session = ProfileSession(profileID: profile) { context.makePage(for: $0) }
        return (session, context)
    }

    private func open(_ url: URL, in session: ProfileSession, _ context: ProfileWebContext) async throws {
        session.submitCommandBar(url.absoluteString)
        let webView = try #require(session.selectedTabID.flatMap(context.webView(for:)))
        try await waitUntil("\(url.path()) loads") { webView.url == url && !webView.isLoading }
    }

    private func savedTab(_ session: ProfileSession) throws -> TabRecord {
        try #require(session.savedSession().tabs.first)
    }

    private func close(_ session: ProfileSession) {
        session.tabs.map(\.id).forEach(session.close)
    }

    @Test func anOrdinaryPageKeepsItsFullStateAndComesBackWithItsHistory() async throws {
        let server = try await PageServer()
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context) = makeSession(profile)
            try await open(server.url("/plain"), in: session, context)
            try await open(server.url("/plain2"), in: session, context)
            try await Task.sleep(for: .milliseconds(300))

            let saved = try savedTab(session)
            #expect(saved.address == server.url("/plain2"))
            #expect(saved.navigationState != nil)
            #expect(saved.navigationStateOSBuild == OSBuild.current)
            close(session)

            let (relaunched, newContext) = makeSession(profile)
            relaunched.restore(SavedSession(tabs: [saved], selectedTabID: saved.id))
            let webView = try #require(newContext.webView(for: saved.id))
            try await waitUntil("the restored page loads") { webView.url == server.url("/plain2") && !webView.isLoading }

            #expect(webView.backForwardList.backList.map(\.url) == [server.url("/plain")])
            #expect(relaunched.selectedTab?.state.canGoBack == true)
            close(relaunched)
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aPageWithAPasswordFieldIsSavedByItsAddressOnly() async throws {
        let server = try await PageServer()
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context) = makeSession(profile)
            try await open(server.url("/login"), in: session, context)
            try await waitUntil("the password field is seen") { session.savedSession().tabs.first?.navigationState == nil }

            #expect(try savedTab(session) == TabRecord(id: try #require(session.selectedTabID),
                                                       address: server.url("/login"), title: "Login"))
            close(session)
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aPasswordFieldAddedAfterTheLoadOrInAFrameCounts() async throws {
        let server = try await PageServer()
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context) = makeSession(profile)
            for path in ["/later", "/framed"] {
                session.openCommandBar(for: .newTab)
                try await open(server.url(path), in: session, context)
                try await waitUntil("the password field of \(path) is seen") {
                    session.savedSession().tabs.last?.navigationState == nil
                }
                #expect(session.savedSession().tabs.last?.address == server.url(path))
            }
            close(session)
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aPageReachedByAPostIsSavedByItsAddressOnlyWhileItIsInTheHistory() async throws {
        let server = try await PageServer()
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context) = makeSession(profile)
            try await open(server.url("/form"), in: session, context)
            #expect(try savedTab(session).navigationState != nil)

            let webView = try #require(session.selectedTabID.flatMap(context.webView(for:)))
            _ = try await webView.evaluateJavaScript("document.forms[0].submit()")
            try await waitUntil("the form posts") { webView.url == server.url("/posted") && !webView.isLoading }

            #expect(try savedTab(session).address == server.url("/posted"))
            #expect(try savedTab(session).navigationState == nil)

            try await open(server.url("/plain"), in: session, context)

            #expect(try savedTab(session).address == server.url("/plain"))
            #expect(try savedTab(session).navigationState == nil)
            close(session)
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aStateWebKitCannotReadFallsBackToTheLastAddress() async throws {
        let server = try await PageServer()
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context) = makeSession(profile)
            let record = TabRecord(id: TabID(), address: server.url("/plain"), title: "Plain",
                                   navigationState: Data("not a navigation state".utf8),
                                   navigationStateOSBuild: OSBuild.current)

            session.restore(SavedSession(tabs: [record], selectedTabID: record.id))
            let webView = try #require(context.webView(for: record.id))
            try await waitUntil("the last address loads") { webView.url == server.url("/plain") && !webView.isLoading }

            #expect(webView.backForwardList.backList.isEmpty)
            close(session)
        }
        await removeDataStoreWhenReleased(profile)
    }
}
