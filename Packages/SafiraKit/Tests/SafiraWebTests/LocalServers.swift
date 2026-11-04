// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Network
import Security

/// A loopback server for the HTTPS-first tests: plain HTTP, TLS with a throwaway self-signed certificate, or a socket
/// that accepts and never answers. It counts the HTTP requests it receives, so a test can prove none arrived.
/// Other tools on the machine probe loopback ports, so only requests addressed to `127.0.0.1:<port>` count.
final class LocalServer: @unchecked Sendable {
    enum Kind { case http, tls, silent }

    private(set) var port: UInt16 = 0
    private let listener: NWListener
    private let queue = DispatchQueue(label: "LocalServer")
    private let lock = NSLock()
    private var requests = 0
    private var lines: [String] = []
    private var hellos = 0
    private var open: [NWConnection] = []

    /// HTTP requests received so far (a TLS client hello is not one).
    var requestCount: Int { lock.withLock { requests } }
    /// The request lines received, for failure messages.
    var requestLines: [String] { lock.withLock { lines } }
    /// TLS client hellos received on a server that does not speak TLS: a client tried HTTPS here.
    var clientHelloCount: Int { lock.withLock { hellos } }

    static func start(_ kind: Kind, title: String = "served") async throws -> LocalServer {
        // A client that hangs up mid-write must not take the test process down.
        signal(SIGPIPE, SIG_IGN)
        let parameters: NWParameters
        switch kind {
        case .tls:
            let options = NWProtocolTLS.Options()
            sec_protocol_options_set_local_identity(options.securityProtocolOptions, sec_identity_create(try selfSignedIdentity())!)
            parameters = NWParameters(tls: options)
        case .http, .silent:
            parameters = NWParameters.tcp
        }
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let server = LocalServer(listener: listener, kind: kind, title: title)
        return try await server.ready()
    }

    /// A loopback port that nothing listens on: connecting to it is refused.
    static func closedPort() async throws -> UInt16 {
        let server = try await start(.http)
        let port = server.port
        server.stop()
        try await Task.sleep(for: .milliseconds(100))
        return port
    }

    private init(listener: NWListener, kind: Kind, title: String) {
        self.listener = listener
        self.kind = kind
        self.title = title
    }

    private let kind: Kind
    private let title: String

    func stop() {
        listener.cancel()
        lock.withLock { open.forEach { $0.cancel() }; open = [] }
    }

    private func ready() async throws -> LocalServer {
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
            listener.start(queue: queue)
        }
        port = listener.port?.rawValue ?? 0
        return self
    }

    private func handle(_ connection: NWConnection) {
        lock.withLock { open.append(connection) }
        connection.start(queue: queue)
        guard kind != .silent else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [self] data, _, _, _ in
            guard let data else { return connection.cancel() }
            let text = String(decoding: data, as: UTF8.self)
            guard text.hasPrefix("GET "), text.lowercased().contains("\r\nhost: 127.0.0.1:\(port)\r\n") else {
                if data.first == 0x16 { lock.withLock { hellos += 1 } }
                return connection.cancel()
            }
            lock.withLock {
                requests += 1
                lines.append(text.replacingOccurrences(of: "\r\n", with: " | "))
            }
            let body = "<!DOCTYPE html><title>\(title)</title><body>\(title)</body>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\n"
                + "Connection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private static func selfSignedIdentity() throws -> SecIdentity {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("safira-tls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = directory.appendingPathComponent("key.pem").path
        let certificate = directory.appendingPathComponent("cert.pem").path
        let bundle = directory.appendingPathComponent("identity.p12").path
        try run("/usr/bin/openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", certificate,
                "-days", "1", "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1")
        try run("/usr/bin/openssl", "pkcs12", "-export", "-inkey", key, "-in", certificate, "-out", bundle,
                "-passout", "pass:test")
        var items: CFArray?
        let status = SecPKCS12Import(try Data(contentsOf: URL(fileURLWithPath: bundle)) as CFData,
                                     [kSecImportExportPassphrase as String: "test"] as CFDictionary, &items)
        guard status == errSecSuccess, let entry = (items as? [[String: Any]])?.first,
              let identity = entry[kSecImportItemIdentity as String]
        else { throw ServerError.identity(status) }
        return identity as! SecIdentity
    }

    private static func run(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ServerError.tool(tool, process.terminationStatus) }
    }

    enum ServerError: Error { case identity(OSStatus), tool(String, Int32) }
}

final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()
    init(_ value: Value) { self.value = value }
    func swap(_ new: Value) -> Value { lock.withLock { let old = value; value = new; return old } }
}
