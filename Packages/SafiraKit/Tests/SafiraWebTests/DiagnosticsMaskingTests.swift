// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import DiagnosticsKit
import Foundation
import Network
import OSLog
import SafiraCore
import SafiraWeb
import Synchronization
import Testing

/// Answers every request on a loopback port with one page whose title and body are recognisable.
private final class LoopbackServer: @unchecked Sendable {
    let listener: NWListener
    let port: UInt16

    init() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { _, _, _, _ in
                let body = "<html><head><title>Secret Quarterly Title</title></head><body>private body</body></html>"
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\n"
                    + "Connection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), contentContext: .finalMessage, isComplete: true,
                                completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = Atomic()
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready where resumed.first():
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error) where resumed.first():
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .global())
        }
        self.listener = listener
        self.port = port
    }

    deinit { listener.cancel() }
}

private final class Atomic: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func first() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        defer { used = true }
        return !used
    }
}

/// The private forms that reached the system log.
private final class RecordingSystemLog: DiagnosticSystemLog {
    private let recorded = Mutex<[String]>([])

    var fullLines: [String] { recorded.withLock { $0 } }

    func channel(category: String) -> any DiagnosticSystemLogChannel { Channel(log: self) }

    private struct Channel: DiagnosticSystemLogChannel {
        let log: RecordingSystemLog

        func isEnabled(_ type: OSLogType) -> Bool { true }

        func write(_ type: OSLogType, redacted: String, full: String?) {
            log.recorded.withLock { $0.append(full ?? redacted) }
        }
    }
}

@MainActor
@Suite struct DiagnosticsMaskingTests {
    /// The end-to-end proof of the masking: a real page with a path, a query and a title is loaded in real WebKit,
    /// and the log written for it keeps the host out of the file and names nothing else of the address anywhere.
    @Test func aRealPageLoadAndAFailedOneAreLoggedWithoutTheirAddress() async throws {
        let server = try await LoopbackServer()
        let systemLog = RecordingSystemLog()
        let logs = FileManager.default.temporaryDirectory
            .appending(path: "safira-web-diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: logs) }
        let profile = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let log = DiagnosticLog(configuration: .safira(subsystem: "test"), flushDelay: .milliseconds(10),
                                    isEnabled: true, systemLog: systemLog)
            log.start { logs }
            context.diagnostics = DiagnosticLogger(category: "navigation", sink: log)
            let page = context.makePage(for: TabID())

            page.load(try #require(URL(string: "http://127.0.0.1:\(server.port)/private/path?token=abc123#frag")), httpsFirst: false)
            let loaded = try await waitForLine(containing: "page-loaded", in: context, logs: logs)
            page.load(try #require(URL(string: "http://127.0.0.1:1/secret-failing-path?q=1")), httpsFirst: false)
            let failed = try await waitForLine(containing: "load-failed", in: context, logs: logs)

            #expect(loaded.contains("notice [navigation] page-loaded host=<private> ms="))
            #expect(failed.hasSuffix("error [navigation] load-failed host=<private> domain=WebKitErrorDomain code=103"))
            #expect(systemLog.fullLines.contains { $0.hasPrefix("page-loaded host=127.0.0.1 ms=") })
            #expect(systemLog.fullLines.contains("load-failed host=127.0.0.1 domain=WebKitErrorDomain code=103"))
            let fileText = try allLogText(in: logs)
            #expect(!fileText.contains("127.0.0.1"))
            let text = fileText + systemLog.fullLines.joined(separator: "\n")
            for forbidden in ["/private", "path", "token", "abc123", "frag", "Secret", "Quarterly", "Title", "http", "secret",
                              "body"] {
                #expect(!text.contains(forbidden), "the log leaks \(forbidden)")
            }
            #expect(page.state.title == "Secret Quarterly Title")
            page.close()
        }
        await removeDataStoreWhenReleased(profile)
    }

    private func waitForLine(containing marker: String, in context: ProfileWebContext, logs: URL) async throws -> String {
        for _ in 0..<150 {
            await context.diagnostics?.sink.flush()
            if let line = try allLogText(in: logs).split(separator: "\n").last(where: { $0.contains(marker) }) {
                return String(line)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        Issue.record("no \(marker) line was logged within 15 seconds")
        return ""
    }

    private func allLogText(in logs: URL) throws -> String {
        guard FileManager.default.fileExists(atPath: logs.path) else { return "" }
        return try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
            .map { try String(contentsOf: $0, encoding: .utf8) }.joined()
    }
}
