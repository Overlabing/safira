// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Network

/// A loopback server of downloadable files, for the download suites. The bodies are literal and known to the tests:
/// byte `i` of any file is `i % 251`.
///
/// - `/small.bin`: 1 000 bytes at once, `application/octet-stream`.
/// - `/slow.bin`: 100 000 bytes in ten chunks, one every 300 ms, with a validator and range support so that a
///   transfer can be continued. `hold(after:)` stops it partway until `release()`, so that a test acting on a running
///   transfer never finds it finished, however long a loaded machine takes to get there.
/// - `/broken.bin`: promises 100 000 bytes without a validator, sends 20 000 and hangs up.
/// - `/notes.txt`: `text/plain` that the browser could show, sent as an attachment.
/// - `/inline.txt`: `text/plain` with no disposition, which the browser shows unless a link says `download`.
/// - `/page.html`: a page with a download link to `/small.bin` and one to `/inline.txt`.
final class DownloadServer: @unchecked Sendable {
    static let smallSize = 1_000
    static let slowSize = 100_000
    private static let chunk = 10_000

    private(set) var port: UInt16 = 0
    private let listener: NWListener
    private let lock = NSLock()
    private var counts: [String: Int] = [:]
    private var ranges: [String] = []
    private var connections: [NWConnection] = []
    private var heldAfter: Int?
    private var stopped = false

    /// Requests received per path.
    func requestCount(_ path: String) -> Int { lock.withLock { counts[path] ?? 0 } }
    /// The `Range` headers received on `/slow.bin`, in order.
    var rangeRequests: [String] { lock.withLock { ranges } }

    static func bytes(_ range: Range<Int>) -> Data {
        Data(range.map { UInt8($0 % 251) })
    }

    func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }

    static func start() async throws -> DownloadServer {
        signal(SIGPIPE, SIG_IGN)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = DownloadServer(listener: try NWListener(using: parameters))
        return try await server.ready()
    }

    private init(listener: NWListener) { self.listener = listener }

    func stop() {
        listener.cancel()
        lock.withLock { stopped = true; connections.forEach { $0.cancel() }; connections = [] }
    }

    /// Every `/slow.bin` transfer, running or to come, sends nothing past this byte of the file until `release()`.
    func hold(after byte: Int) { lock.withLock { heldAfter = byte } }

    func release() { lock.withLock { heldAfter = nil } }

    private func isHeld(at offset: Int) -> Bool {
        lock.withLock { !stopped && (heldAfter.map { offset >= $0 } ?? false) }
    }

    private func ready() async throws -> DownloadServer {
        listener.newConnectionHandler = { [self] connection in handle(connection) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = Locked(false)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready: if resumed.swap(true) == false { continuation.resume() }
                case .failed(let error): if resumed.swap(true) == false { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.start(queue: .global())
        }
        port = listener.port?.rawValue ?? 0
        return self
    }

    private func handle(_ connection: NWConnection) {
        lock.withLock { connections.append(connection) }
        connection.start(queue: .global())
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [self] data, _, _, _ in
            guard let data else { return connection.cancel() }
            let request = String(decoding: data, as: UTF8.self)
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let range = request.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("range:") }
                .map { $0.dropFirst(6).trimmingCharacters(in: .whitespaces) }
            lock.withLock {
                counts[path, default: 0] += 1
                if path == "/slow.bin", let range { ranges.append(range) }
            }
            Task { await respond(to: path, range: range, on: connection) }
        }
    }

    private func respond(to path: String, range: String?, on connection: NWConnection) async {
        switch path {
        case "/small.bin":
            await send(connection, status: "200 OK", type: "application/octet-stream",
                       headers: "ETag: \"small\"\r\n", body: Self.bytes(0..<Self.smallSize))
        case "/notes.txt":
            await send(connection, status: "200 OK", type: "text/plain",
                       headers: "Content-Disposition: attachment; filename=\"notes.txt\"\r\n", body: Data("hello\n".utf8))
        case "/inline.txt":
            await send(connection, status: "200 OK", type: "text/plain", body: Data("inline\n".utf8))
        case "/page.html":
            let body = #"<!doctype html><title>page</title><a id="link" href="/small.bin" download>get</a>"#
                + #"<a id="inline" href="/inline.txt" download>text</a>"#
            await send(connection, status: "200 OK", type: "text/html", body: Data(body.utf8))
        case "/slow.bin":
            await sendSlow(connection, range: range)
        case "/broken.bin":
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(Self.slowSize)\r\n"
                + "Connection: close\r\n\r\n"
            await write(connection, Data(head.utf8) + Self.bytes(0..<20_000))
            try? await Task.sleep(for: .milliseconds(200))
            connection.cancel()
        default:
            await send(connection, status: "404 Not Found", type: "text/plain", body: Data("not found".utf8))
        }
    }

    private func send(_ connection: NWConnection, status: String, type: String, headers: String = "", body: Data) async {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n\(headers)"
            + "Connection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, contentContext: .finalMessage, isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    private func sendSlow(_ connection: NWConnection, range: String?) async {
        var start = 0
        if let range, range.hasPrefix("bytes="), let first = range.dropFirst(6).split(separator: "-").first,
           let value = Int(first) {
            start = value
        }
        let status = start > 0 ? "206 Partial Content" : "200 OK"
        let contentRange = start > 0 ? "Content-Range: bytes \(start)-\(Self.slowSize - 1)/\(Self.slowSize)\r\n" : ""
        let head = "HTTP/1.1 \(status)\r\nContent-Type: application/octet-stream\r\nAccept-Ranges: bytes\r\n"
            + "ETag: \"slow\"\r\nLast-Modified: Wed, 21 Oct 2015 07:28:00 GMT\r\n\(contentRange)"
            + "Content-Length: \(Self.slowSize - start)\r\nConnection: close\r\n\r\n"
        await write(connection, Data(head.utf8))
        var offset = start
        while offset < Self.slowSize {
            while isHeld(at: offset) { try? await Task.sleep(for: .milliseconds(20)) }
            let end = min(Self.slowSize, offset + Self.chunk)
            await write(connection, Self.bytes(offset..<end))
            offset = end
            if offset < Self.slowSize { try? await Task.sleep(for: .milliseconds(300)) }
        }
        connection.cancel()
    }

    private func write(_ connection: NWConnection, _ data: Data) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in continuation.resume() })
        }
    }
}
