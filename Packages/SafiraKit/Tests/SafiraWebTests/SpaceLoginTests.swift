// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Network
import SafiraCore
import SafiraSession
import SafiraWeb
import Testing
import WebKit

/// A loopback site with a sign-in: `/login` sets a session cookie, `/whoami` names the session cookie it received in
/// its title, or "anonymous".
private final class LoginServer: @unchecked Sendable {
    let listener: NWListener
    let port: UInt16

    init() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let lines = data.map { String(decoding: $0, as: UTF8.self).components(separatedBy: "\r\n") } ?? []
                let path = lines.first.map { String($0.split(separator: " ").dropFirst().first ?? "") } ?? ""
                let cookie = lines.first { $0.lowercased().hasPrefix("cookie:") }
                    .map { $0.dropFirst("cookie:".count).trimmingCharacters(in: .whitespaces) }
                let (title, extraHeader) = switch path {
                case "/login": ("Signed in", "Set-Cookie: session=alice; Path=/; HttpOnly\r\n")
                case "/whoami": (cookie ?? "anonymous", "")
                default: ("Missing", "")
                }
                let body = "<!doctype html><html><head><title>\(title)</title></head><body></body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\n"
                    + "Cache-Control: no-store\r\n\(extraHeader)Connection: close\r\n\r\n\(body)"
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

/// The Spaces of a Profile share its website data store, so a sign-in in one Space is seen in the others, and
/// deleting a Space keeps it (ADR 0002). Real WebKit pages.
@MainActor
@Suite(.serialized) struct SpaceLoginTests {
    private func makeSession(_ profile: ProfileID) -> (ProfileSession, ProfileWebContext) {
        let context = ProfileWebContext(profileID: profile)
        let session = ProfileSession(profileID: profile) { context.makePage(for: $0) }
        return (session, context)
    }

    /// Opens the address in a new Tab of the active Space and returns the page's title once it has loaded.
    private func titleAfterOpening(_ url: URL, in session: ProfileSession, _ context: ProfileWebContext)
        async throws -> String? {
        session.openCommandBar(for: .newTab)
        session.submitCommandBar(url.absoluteString)
        let webView = try #require(session.selectedTabID.flatMap(context.webView(for:)))
        try await waitUntil("\(url.path()) loads") { webView.url == url && !webView.isLoading && webView.title != "" }
        return webView.title
    }

    private func closeAll(_ session: ProfileSession) {
        for space in session.spaces {
            space.tabs.map(\.id).forEach(session.close)
        }
    }

    @Test func aSignInInOneSpaceIsSeenInAnotherSpaceOfTheSameProfileOnly() async throws {
        let server = try await LoginServer()
        let profile = ProfileID(rawValue: UUID())
        let otherProfile = ProfileID(rawValue: UUID())
        do {
            let (session, context) = makeSession(profile)
            let (other, otherContext) = makeSession(otherProfile)

            #expect(try await titleAfterOpening(server.url("/login"), in: session, context) == "Signed in")
            session.createSpace(name: "Reading", emoji: "📚")
            #expect(try await titleAfterOpening(server.url("/whoami"), in: session, context) == "session=alice")
            #expect(try await titleAfterOpening(server.url("/whoami"), in: other, otherContext) == "anonymous")

            #expect(session.spaces.map { $0.tabs.count } == [1, 1])
            closeAll(session)
            closeAll(other)
        }
        await removeDataStoreWhenReleased(profile)
        await removeDataStoreWhenReleased(otherProfile)
    }

    @Test func deletingTheSpaceWhereTheUserSignedInKeepsTheLogin() async throws {
        let server = try await LoginServer()
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context) = makeSession(profile)
            let home = session.activeSpaceID
            let reading = session.createSpace(name: "Reading", emoji: "📚")
            #expect(try await titleAfterOpening(server.url("/login"), in: session, context) == "Signed in")
            let signInTab = try #require(session.selectedTabID)

            session.deleteSpace(reading)

            #expect(session.activeSpaceID == home)
            #expect(context.webView(for: signInTab) == nil)
            #expect(try await titleAfterOpening(server.url("/whoami"), in: session, context) == "session=alice")
            let cookies = await context.dataStore.httpCookieStore.allCookies()
            #expect(cookies.map { "\($0.name)=\($0.value)" } == ["session=alice"])
            closeAll(session)
        }
        await removeDataStoreWhenReleased(profile)
    }
}
