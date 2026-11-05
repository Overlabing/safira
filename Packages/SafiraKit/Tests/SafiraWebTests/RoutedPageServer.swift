// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Network

/// A loopback server whose pages the test writes out literally: one fixed answer per path, any status, any headers.
/// A path it has no page for answers 404. It serves HTTP only, and keeps the head of every request it received.
final class RoutedPageServer: @unchecked Sendable {
    struct Page: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var body = ""

        static func html(_ body: String) -> Page { Page(body: "<!DOCTYPE html><html><body>\(body)</body></html>") }

        static func redirect(to location: String) -> Page { Page(status: 302, headers: ["Location": location]) }
    }

    private(set) var port: UInt16 = 0
    private let listener: NWListener
    private let pages: [String: Page]
    private let lock = NSLock()
    private var open: [NWConnection] = []
    private var heads: [String] = []

    /// The request line and headers of every request received, in order, each line ending in a line break.
    var requests: [String] { lock.withLock { heads } }

    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    static func start(_ pages: [String: Page]) async throws -> RoutedPageServer {
        signal(SIGPIPE, SIG_IGN)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = RoutedPageServer(listener: try NWListener(using: parameters), pages: pages)
        return try await server.ready()
    }

    private init(listener: NWListener, pages: [String: Page]) {
        self.listener = listener
        self.pages = pages
    }

    func stop() {
        listener.cancel()
        lock.withLock { open.forEach { $0.cancel() }; open = [] }
    }

    private func ready() async throws -> RoutedPageServer {
        listener.newConnectionHandler = { [self] connection in handle(connection) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = Locked(false)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.swap(true) == false { continuation.resume() }
                case .failed(let error):
                    if resumed.swap(true) == false { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.start(queue: .global())
        }
        port = listener.port?.rawValue ?? 0
        return self
    }

    private func handle(_ connection: NWConnection) {
        lock.withLock { open.append(connection) }
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, _, _ in
            guard let data else { return connection.cancel() }
            let text = String(decoding: data, as: UTF8.self)
            let line = text.components(separatedBy: "\r\n").first ?? ""
            let head = text.components(separatedBy: "\r\n\r\n").first ?? text
            lock.withLock { heads.append(head.replacingOccurrences(of: "\r\n", with: "\n") + "\n") }
            let target = line.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
            let page = pages[path] ?? Page(status: 404, body: "not found")
            let reason = switch page.status { case 200: "OK"; case 302: "Found"; default: "Not Found" }
            var response = "HTTP/1.1 \(page.status) \(reason)\r\nContent-Type: text/html\r\n"
            response += "Content-Length: \(page.body.utf8.count)\r\nCache-Control: no-store\r\n"
            for (name, value) in page.headers { response += "\(name): \(value)\r\n" }
            response += "Connection: close\r\n\r\n\(page.body)"
            connection.send(content: Data(response.utf8), contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
