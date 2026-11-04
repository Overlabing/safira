// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Network

/// A loopback stand-in for a site and its identity provider, on two origins of one port: the app at `127.0.0.1` and the
/// provider at `localhost`, which are different sites for cookies and for `postMessage`. It signs nobody in anywhere
/// real. The flow is the usual popup sign-in:
///
/// 1. `/app` has a button that runs `window.open(<provider>/authorize, "signin", "width=480,height=640")`;
/// 2. the provider sets its own session cookie, then posts the authorization code to `window.opener` for the app's
///    origin and closes the popup;
/// 3. the app checks the sender's origin, trades the code at `/session` for its own session cookie, and puts
///    "app: signed in as alice" in its title.
final class SignInSite: @unchecked Sendable {
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
                let target = lines.first.map { String($0.split(separator: " ").dropFirst().first ?? "") } ?? ""
                let host = lines.first { $0.lowercased().hasPrefix("host:") }
                    .map { $0.dropFirst("host:".count).trimmingCharacters(in: .whitespaces) } ?? ""
                let cookie = lines.first { $0.lowercased().hasPrefix("cookie:") }
                    .map { $0.dropFirst("cookie:".count).trimmingCharacters(in: .whitespaces) }
                let (body, headers) = Self.page(for: target, host: host, cookie: cookie, port: listener.port?.rawValue ?? 0)
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\n"
                    + "Cache-Control: no-store\r\n\(headers)Connection: close\r\n\r\n\(body)"
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
        port = try await iterator.next() ?? 0
    }

    /// An address on the app's origin.
    func app(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    /// An address on the identity provider's origin.
    func provider(_ path: String) -> URL { URL(string: "http://localhost:\(port)\(path)")! }

    deinit { listener.cancel() }

    private static func page(for target: String, host: String, cookie: String?, port: UInt16) -> (String, String) {
        let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        let appOrigin = "http://127.0.0.1:\(port)"
        let providerOrigin = "http://localhost:\(port)"
        func html(_ title: String, _ script: String = "", _ body: String = "") -> String {
            "<!doctype html><html><head><title>\(title)</title></head><body>\(body)<script>\(script)</script></body></html>"
        }
        if host.hasPrefix("localhost") {
            switch path {
            case "/authorize":
                return (html("provider: signing in", """
                    document.title = window.opener ? "provider: posting" : "provider: no opener";
                    if (window.opener) {
                        window.opener.postMessage({ state: "xyz", code: "abc" }, "\(appOrigin)");
                        window.close();
                    }
                    """), "Set-Cookie: idp_session=1; Path=/; HttpOnly\r\n")
            case "/hold":
                return (html("provider: waiting"), "Set-Cookie: idp_session=1; Path=/; HttpOnly\r\n")
            default:
                return (html("provider: \(cookie ?? "anonymous")"), "")
            }
        }
        switch path {
        case "/app":
            return (html("app: signed out", """
                function openSignIn(url) { window.open(url, "signin", "width=480,height=640"); }
                addEventListener("message", async (event) => {
                    if (event.origin !== "\(providerOrigin)" || event.data.state !== "xyz") return;
                    const reply = await fetch("/session?code=" + event.data.code);
                    document.title = "app: " + await reply.text();
                });
                """, """
                <button id="signin" onclick="openSignIn('\(providerOrigin)/authorize?state=xyz')">Sign in</button>
                <button id="hold" onclick="openSignIn('\(providerOrigin)/hold')">Open and stay</button>
                <button id="plain" onclick="window.open('/docs')">Open a page</button>
                <a id="blank" href="/docs" target="_blank">Docs</a>
                """), "")
        case "/session":
            return ("signed in as alice", "Set-Cookie: app_session=alice; Path=/; HttpOnly\r\n")
        case "/whoami":
            return (html("app: \(cookie ?? "anonymous")"), "")
        default:
            return (html("app: \(path)"), "")
        }
    }
}
