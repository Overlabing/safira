// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Foundation
import Network
import WebKit

/// An app an extension reaches with `runtime.connectNative` or `runtime.sendNativeMessage`, through the app's own
/// local bridge: a TCP port on the loopback that speaks Native Messaging framing.
public struct NativeApplication: Hashable, Sendable {
    /// The name the extension passes to `connectNative`.
    public let applicationIdentifier: String
    /// The only extension relayed to it: the identifier derived from its manifest `key` (ExtensionIdentity).
    public let extensionIdentifier: String
    public let bundleIdentifier: String
    public let port: UInt16
    /// How long to wait for the bridge to answer after launching the app.
    public let launchWait: Duration

    public init(applicationIdentifier: String, extensionIdentifier: String, bundleIdentifier: String, port: UInt16,
                launchWait: Duration = .seconds(10)) {
        self.applicationIdentifier = applicationIdentifier
        self.extensionIdentifier = extensionIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.port = port
        self.launchWait = launchWait
    }

    /// Verrou's bridge, which its own native host relays to in Brave (verrou-bridge, `lib.rs` and `server.rs`).
    public static let verrou = NativeApplication(applicationIdentifier: "app.verrou.bridge",
                                                 extensionIdentifier: "pmdlgnpbjfdnmpeadbecmgfoojmocibg",
                                                 bundleIdentifier: "app.verrou.mac", port: 41738)
}

/// Native Messaging framing: a 4-byte little-endian length, then that many bytes of JSON.
struct NativeMessageFrames {
    /// The largest frame Verrou's bridge accepts (`MAX_FRAME`); a longer one ends the connection.
    static let maximumLength = 1024 * 1024

    struct Invalid: Error, Equatable {
        let length: Int
    }

    private var buffer = Data()

    static func encode(_ message: Any) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: message, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
        guard !body.isEmpty, body.count <= maximumLength else { throw Invalid(length: body.count) }
        var length = UInt32(body.count).littleEndian
        return Data(bytes: &length, count: 4) + body
    }

    static func decode(_ body: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])
    }

    /// Adds bytes read from the connection and returns the bodies of the frames now complete, in order.
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var bodies: [Data] = []
        while buffer.count >= 4 {
            let start = buffer.startIndex
            let length = buffer[start..<start + 4].reversed().reduce(0) { $0 << 8 | Int($1) }
            guard length > 0, length <= Self.maximumLength else { throw Invalid(length: length) }
            guard buffer.count >= 4 + length else { break }
            bodies.append(Data(buffer[start + 4..<start + 4 + length]))
            buffer.removeSubrange(start..<start + 4 + length)
        }
        return bodies
    }
}

/// The extension's end of a native connection: `WKWebExtension.MessagePort` in the app, a fake in the tests.
@MainActor
protocol NativeMessagePort: AnyObject {
    var applicationIdentifier: String? { get }
    func onMessage(_ handler: @escaping @MainActor (Any?) -> Void)
    func onDisconnect(_ handler: @escaping @MainActor () -> Void)
    func send(_ message: Any)
    func disconnect()
}

/// The error the extension's port receives when the app's bridge does not answer, even after a launch; Verrou's
/// extension handles it (`bridge.js`), as it does from Verrou's own native host.
let nativeAppUnavailable: [String: String] = ["type": "error", "code": "app_unavailable"]

/// Relays an extension's native messages to the app's local bridge, frame by frame, in both directions. It never
/// reads them: Verrou's messages are end-to-end encrypted between its extension and its app, so Safira only ever sees
/// ciphertext. One TCP connection per port, open as long as both ends keep it.
@MainActor
public final class NativeMessagingRelay {
    struct Refused: LocalizedError {
        let applicationIdentifier: String?
        var errorDescription: String? { "No native application \(applicationIdentifier ?? "") for this extension" }
    }

    private let applications: [NativeApplication]
    private let host: String
    /// Opens the app without bringing it to the front; the tests replace it so that no real app starts.
    private let launch: @MainActor (NativeApplication) -> Void
    private var sessions: [ObjectIdentifier: NativeRelaySession] = [:]

    init(applications: [NativeApplication] = [.verrou], host: String = "127.0.0.1",
         launch: @escaping @MainActor (NativeApplication) -> Void = NativeMessagingRelay.openInBackground) {
        self.applications = applications
        self.host = host
        self.launch = launch
    }

    /// The ports currently relayed.
    var openPortCount: Int { sessions.count }

    /// Starts relaying `port`, or throws when no app is registered under its name for this extension.
    func connect(_ port: any NativeMessagePort, extensionIdentifier: String) throws {
        let application = try self.application(port.applicationIdentifier, extensionIdentifier)
        let key = ObjectIdentifier(port)
        let session = NativeRelaySession(port: port, connection: bridgeConnection(to: application)) { [weak self] in
            self?.sessions[key] = nil
        }
        sessions[key] = session
        session.start()
    }

    /// `runtime.sendNativeMessage`: one message, the bridge's first answer, then the connection closes.
    func sendMessage(_ message: Any, applicationIdentifier: String?, extensionIdentifier: String) async throws -> Any {
        let application = try self.application(applicationIdentifier, extensionIdentifier)
        let frame = try NativeMessageFrames.encode(message)
        guard let connection = await bridgeConnection(to: application)() else { return nativeAppUnavailable }
        defer { connection.cancel() }
        return try await connection.exchange(frame)
    }

    private func application(_ applicationIdentifier: String?, _ extensionIdentifier: String) throws -> NativeApplication {
        guard let application = applications.first(where: {
            $0.applicationIdentifier == applicationIdentifier && $0.extensionIdentifier == extensionIdentifier
        }) else { throw Refused(applicationIdentifier: applicationIdentifier) }
        return application
    }

    /// Connects to the bridge; if it does not answer, launches the app once and retries until `launchWait` is over,
    /// as Verrou's own native host does (`connect_to_app`).
    private func bridgeConnection(to application: NativeApplication) -> @MainActor () async -> BridgeConnection? {
        let host = host
        let launch = launch
        return {
            if let connection = await BridgeConnection.open(host: host, port: application.port) { return connection }
            guard !Task.isCancelled else { return nil }
            launch(application)
            let deadline = ContinuousClock.now + application.launchWait
            while ContinuousClock.now < deadline {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return nil }
                if let connection = await BridgeConnection.open(host: host, port: application.port) { return connection }
            }
            return nil
        }
    }

    static func openInBackground(_ application: NativeApplication) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: application.bundleIdentifier) else {
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }
}

/// One relayed port: what the extension posts goes to the bridge as frames, what the bridge sends goes back to the
/// port. Messages posted before the connection is ready wait for it, in order. Either end closing closes the other.
@MainActor
final class NativeRelaySession {
    private let port: any NativeMessagePort
    private let makeConnection: @MainActor () async -> BridgeConnection?
    private let onClose: @MainActor () -> Void
    private var connection: BridgeConnection?
    private var waiting: [Data] = []
    private var isClosed = false
    private var connecting: Task<Void, Never>?

    init(port: any NativeMessagePort, connection: @escaping @MainActor () async -> BridgeConnection?,
         onClose: @escaping @MainActor () -> Void) {
        self.port = port
        makeConnection = connection
        self.onClose = onClose
    }

    func start() {
        port.onMessage { [weak self] message in self?.forward(message) }
        port.onDisconnect { [weak self] in self?.close(disconnectingPort: false) }
        connecting = Task { [weak self] in
            guard let self else { return }
            let connection = await makeConnection()
            guard !isClosed else { return connection?.cancel() ?? () }
            guard let connection else {
                port.send(nativeAppUnavailable)
                return close(disconnectingPort: true)
            }
            self.connection = connection
            connection.receive { [weak self] message in
                self?.port.send(message)
            } onEnd: { [weak self] in
                self?.close(disconnectingPort: true)
            }
            for frame in waiting { connection.send(frame) }
            waiting = []
        }
    }

    private func forward(_ message: Any?) {
        guard !isClosed, let message, let frame = try? NativeMessageFrames.encode(message) else {
            // A message the bridge could not take ends the connection, as the bridge itself would.
            return close(disconnectingPort: true)
        }
        if let connection { connection.send(frame) } else { waiting.append(frame) }
    }

    private func close(disconnectingPort: Bool) {
        guard !isClosed else { return }
        isClosed = true
        connecting?.cancel()
        connection?.cancel()
        connection = nil
        waiting = []
        if disconnectingPort { port.disconnect() }
        onClose()
    }
}

/// A TCP connection to a bridge on the loopback. Its events are delivered on the main queue.
@MainActor
final class BridgeConnection {
    private let connection: NWConnection
    private var frames = NativeMessageFrames()

    private init(_ connection: NWConnection) {
        self.connection = connection
    }

    /// The connection once ready, or nil when nothing answers within a second (refused, or no route).
    static func open(host: String, port: UInt16) async -> BridgeConnection? {
        guard let port = NWEndpoint.Port(rawValue: port) else { return nil }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let opened = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let once = Once(done)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: once.resume(true)
                case .waiting, .failed, .cancelled: once.resume(false)
                default: break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { once.resume(false) }
        }
        connection.stateUpdateHandler = nil
        guard opened else {
            connection.cancel()
            return nil
        }
        return BridgeConnection(connection)
    }

    func send(_ frame: Data) {
        connection.send(content: frame, completion: .idempotent)
    }

    /// Delivers each complete frame's JSON, then `onEnd` once when the bridge closes, fails or sends a bad frame.
    func receive(_ onMessage: @escaping @MainActor (Any) -> Void, onEnd: @escaping @MainActor () -> Void) {
        receiveBodies({ body in
            guard let message = try? NativeMessageFrames.decode(body) else { return self.endOnBadFrame(onEnd) }
            onMessage(message)
        }, onEnd: onEnd)
    }

    private func endOnBadFrame(_ onEnd: @MainActor () -> Void) {
        connection.cancel()
        onEnd()
    }

    private func receiveBodies(_ onBody: @escaping @MainActor (Data) -> Void, onEnd: @escaping @MainActor () -> Void) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: MainActor.assumeIsolated { onEnd() }
            default: break
            }
        }
        readMore(onBody, onEnd)
    }

    /// Sends one frame and returns the first frame that comes back.
    func exchange(_ frame: Data) async throws -> Any {
        send(frame)
        let body = try await withCheckedThrowingContinuation { (done: CheckedContinuation<Data, any Error>) in
            let answer = FirstAnswer(done)
            receiveBodies { answer.give(.success($0)) } onEnd: {
                answer.give(.failure(WKWebExtension.MessagePort.Error(.notConnected)))
            }
        }
        return try NativeMessageFrames.decode(body)
    }

    func cancel() {
        connection.cancel()
    }

    private func readMore(_ onMessage: @escaping @MainActor (Data) -> Void, _ onEnd: @escaping @MainActor () -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            MainActor.assumeIsolated {
                self?.read(data, ended: isComplete || error != nil, onMessage, onEnd)
            }
        }
    }

    private func read(_ data: Data?, ended: Bool, _ onMessage: @escaping @MainActor (Data) -> Void,
                      _ onEnd: @escaping @MainActor () -> Void) {
        do {
            for body in try frames.append(data ?? Data()) {
                onMessage(body)
            }
        } catch {
            connection.cancel()
            return onEnd()
        }
        guard !ended else {
            connection.cancel()
            return onEnd()
        }
        readMore(onMessage, onEnd)
    }
}

/// Resumes a continuation on its first call only: a connection reports several states, and the timeout may fire too.
private final class Once<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

@MainActor
private final class FirstAnswer {
    private var continuation: CheckedContinuation<Data, any Error>?

    init(_ continuation: CheckedContinuation<Data, any Error>) {
        self.continuation = continuation
    }

    func give(_ result: Result<Data, any Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}

/// Verrou's extension holds the real port: WebKit disconnects it when the port is released, so the session keeps it.
@MainActor
final class WebKitMessagePort: NativeMessagePort {
    private let port: WKWebExtension.MessagePort

    init(_ port: WKWebExtension.MessagePort) {
        self.port = port
    }

    var applicationIdentifier: String? { port.applicationIdentifier }

    func onMessage(_ handler: @escaping @MainActor (Any?) -> Void) {
        port.messageHandler = { message, _ in handler(message) }
    }

    func onDisconnect(_ handler: @escaping @MainActor () -> Void) {
        port.disconnectHandler = { _ in handler() }
    }

    func send(_ message: Any) {
        port.sendMessage(message, completionHandler: nil)
    }

    func disconnect() {
        port.disconnect()
    }
}
