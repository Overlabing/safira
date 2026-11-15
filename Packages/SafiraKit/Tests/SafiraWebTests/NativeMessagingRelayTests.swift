// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Network
@testable import SafiraWeb
import Testing
import WebKit

/// The native messaging relay against a fake bridge on a random loopback port: no real Verrou is reached or launched.
@MainActor
@Suite(.serialized) struct NativeMessagingRelayTests {
    static let fixtureID = "pfikphmpnbnmihdgfbljkjgfnamcpjme"

    // MARK: Framing

    @Test func aFrameIsALittleEndianLengthThenTheJSON() throws {
        let frame = try NativeMessageFrames.encode(["type": "pairing", "name": "Safira é"])
        let body = Data(#"{"name":"Safira é","type":"pairing"}"#.utf8)
        #expect(body.count == 37)
        #expect(Array(frame.prefix(4)) == [37, 0, 0, 0])
        #expect(try JSONSerialization.jsonObject(with: frame.dropFirst(4)) as? NSDictionary
            == ["type": "pairing", "name": "Safira é"])
    }

    @Test func framesSplitAcrossReadsComeOutWholeAndInOrder() throws {
        var frames = NativeMessageFrames()
        let first = try NativeMessageFrames.encode(["n": 1])
        let second = try NativeMessageFrames.encode(["n": 2])
        let bytes = first + second
        #expect(try frames.append(bytes.prefix(3)) == [])
        #expect(try frames.append(bytes.dropFirst(3).prefix(first.count)) == [Data(#"{"n":1}"#.utf8)])
        #expect(try frames.append(bytes.dropFirst(3 + first.count)) == [Data(#"{"n":2}"#.utf8)])
    }

    @Test func anEmptyOrOversizedFrameIsRefused() {
        var empty = NativeMessageFrames()
        #expect(throws: NativeMessageFrames.Invalid(length: 0)) { try empty.append(Data([0, 0, 0, 0])) }
        var oversized = NativeMessageFrames()
        #expect(throws: NativeMessageFrames.Invalid(length: 1_048_577)) { try oversized.append(Data([1, 0, 16, 0])) }
        #expect(throws: NativeMessageFrames.Invalid.self) {
            try NativeMessageFrames.encode(String(repeating: "x", count: NativeMessageFrames.maximumLength))
        }
    }

    // MARK: Relay

    @Test func messagesGoToTheBridgeAsFramesAndItsFramesComeBackToThePort() async throws {
        let bridge = try await FakeBridge.start()
        defer { bridge.stop() }
        let relay = NativeMessagingRelay(applications: [Self.application(port: bridge.port)]) { _ in
            Issue.record("the bridge answered: nothing should be launched")
        }
        let port = FakePort("app.safira.test")

        try relay.connect(port, extensionIdentifier: Self.fixtureID)
        // Posted before the connection is ready: it waits, then goes first.
        port.post(["type": "pair", "name": "Safira — Work"])
        try await waitUntil("the bridge received the message") { bridge.received(0).count == 1 }
        #expect(bridge.received(0) == [Data(#"{"name":"Safira — Work","type":"pair"}"#.utf8)])

        // Sent in two pieces, the way TCP may deliver it.
        let reply = try NativeMessageFrames.encode(["type": "pairing", "key": "BASE64", "client": "c1"])
        bridge.send(reply.prefix(6), on: 0)
        try await Task.sleep(for: .milliseconds(50))
        bridge.send(reply.dropFirst(6), on: 0)
        try await waitUntil("the port received the bridge's frame") { port.received.count == 1 }
        #expect(port.received.first as? NSDictionary == ["type": "pairing", "key": "BASE64", "client": "c1"])
        #expect(!port.isDisconnected)
        #expect(relay.openPortCount == 1)
    }

    @Test func whenTheExtensionDisconnectsTheConnectionCloses() async throws {
        let bridge = try await FakeBridge.start()
        defer { bridge.stop() }
        let relay = NativeMessagingRelay(applications: [Self.application(port: bridge.port)]) { _ in }
        let port = FakePort("app.safira.test")
        try relay.connect(port, extensionIdentifier: Self.fixtureID)
        port.post(["type": "status"])
        try await waitUntil("the bridge received the message") { bridge.received(0).count == 1 }

        port.disconnectFromExtension()
        try await waitUntil("the bridge saw the connection end") { bridge.hasEnded(0) }
        #expect(relay.openPortCount == 0)
    }

    @Test func whenTheBridgeClosesThePortDisconnectsAndANewPortStartsCleanly() async throws {
        let bridge = try await FakeBridge.start()
        defer { bridge.stop() }
        let relay = NativeMessagingRelay(applications: [Self.application(port: bridge.port)]) { _ in }
        let first = FakePort("app.safira.test")
        try relay.connect(first, extensionIdentifier: Self.fixtureID)
        first.post(["n": 1])
        try await waitUntil("the first connection carried the message") { bridge.received(0).count == 1 }

        bridge.close(0)
        try await waitUntil("the port was disconnected") { first.isDisconnected }
        #expect(relay.openPortCount == 0)

        let second = FakePort("app.safira.test")
        try relay.connect(second, extensionIdentifier: Self.fixtureID)
        second.post(["n": 2])
        try await waitUntil("a second connection carried the next message") { bridge.received(1).count == 1 }
        #expect(bridge.received(1) == [Data(#"{"n":2}"#.utf8)])
        #expect(!second.isDisconnected)
    }

    @Test func whenNothingAnswersTheAppIsLaunchedOnceThenThePortGetsAppUnavailable() async throws {
        let closedPort = try await FakeBridge.unusedPort()
        var launched: [String] = []
        let relay = NativeMessagingRelay(applications: [Self.application(port: closedPort, wait: .milliseconds(600))]) {
            launched.append($0.bundleIdentifier)
        }
        let port = FakePort("app.safira.test")
        try relay.connect(port, extensionIdentifier: Self.fixtureID)
        port.post(["type": "status"])

        try await waitUntil("the port was disconnected") { port.isDisconnected }
        #expect(launched == ["app.safira.test.mac"])
        #expect(port.received.count == 1)
        #expect(port.received.first as? NSDictionary == ["type": "error", "code": "app_unavailable"])
        #expect(relay.openPortCount == 0)
    }

    @Test func aPortClosedWhileTheBridgeIsAwaitedStopsWaiting() async throws {
        let closedPort = try await FakeBridge.unusedPort()
        var launched = 0
        let relay = NativeMessagingRelay(applications: [Self.application(port: closedPort, wait: .seconds(5))]) { _ in
            launched += 1
        }
        let port = FakePort("app.safira.test")
        try relay.connect(port, extensionIdentifier: Self.fixtureID)
        port.post(["type": "status"])
        try await waitUntil("the app was launched") { launched == 1 }

        port.disconnectFromExtension()
        #expect(relay.openPortCount == 0)
        try await Task.sleep(for: .milliseconds(600))
        #expect(port.received.isEmpty)
        #expect(launched == 1)
    }

    @Test func aBridgeThatComesUpAfterTheLaunchIsReached() async throws {
        let closedPort = try await FakeBridge.unusedPort()
        var bridge: FakeBridge?
        let relay = NativeMessagingRelay(applications: [Self.application(port: closedPort)]) { _ in
            Task { bridge = try await FakeBridge.start(port: closedPort) }
        }
        defer { bridge?.stop() }
        let port = FakePort("app.safira.test")
        try relay.connect(port, extensionIdentifier: Self.fixtureID)
        port.post(["type": "status"])
        try await waitUntil("the launched bridge received the message") { bridge?.received(0).count == 1 }
        #expect(!port.isDisconnected)
    }

    @Test func anotherApplicationOrAnotherExtensionIsRefused() async throws {
        let relay = NativeMessagingRelay(applications: [Self.application(port: 9)]) { _ in
            Issue.record("a refused port launched an app")
        }
        #expect(throws: NativeMessagingRelay.Refused.self) {
            try relay.connect(FakePort("com.other.app"), extensionIdentifier: Self.fixtureID)
        }
        #expect(throws: NativeMessagingRelay.Refused.self) {
            try relay.connect(FakePort("app.safira.test"), extensionIdentifier: "abcdefghijklmnopabcdefghijklmnop")
        }
        await #expect(throws: NativeMessagingRelay.Refused.self) {
            try await relay.sendMessage(["n": 1], applicationIdentifier: nil, extensionIdentifier: Self.fixtureID)
        }
        #expect(relay.openPortCount == 0)
    }

    @Test func aOneTimeMessageGetsTheBridgesFirstFrame() async throws {
        let bridge = try await FakeBridge.start(answer: ["type": "response", "data": "SEALED"])
        defer { bridge.stop() }
        let relay = NativeMessagingRelay(applications: [Self.application(port: bridge.port)]) { _ in }
        let reply = try await relay.sendMessage(["type": "request"], applicationIdentifier: "app.safira.test",
                                                extensionIdentifier: Self.fixtureID)
        #expect(reply as? NSDictionary == ["type": "response", "data": "SEALED"])
        #expect(bridge.received(0) == [Data(#"{"type":"request"}"#.utf8)])
        try await waitUntil("the one-time connection was closed") { bridge.hasEnded(0) }
    }

    @Test func theRealVerrouEntryNamesItsBridge() {
        #expect(NativeApplication.verrou == NativeApplication(
            applicationIdentifier: "app.verrou.bridge", extensionIdentifier: "pmdlgnpbjfdnmpeadbecmgfoojmocibg",
            bundleIdentifier: "app.verrou.mac", port: 41738, launchWait: .seconds(10)))
    }

    // MARK: Through WebKit

    /// A real extension's `connectNative` port, relayed both ways, and reopened after the bridge closes it.
    @Test func anExtensionsPortIsRelayedBothWaysAndReconnectsAfterTheBridgeCloses() async throws {
        let bridge = try await FakeBridge.start()
        defer { bridge.stop() }
        let folder = try Self.nativeExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = try ExtensionHostTests.profile()
        let host = try #require(profile.extensions)
        host.nativeMessaging = NativeMessagingRelay(applications: [Self.application(port: bridge.port)]) { _ in }
        try await host.loadUnpacked(at: folder)
        try await ExtensionHostTests.loadBackgroundContent(of: profile)

        try await waitUntil("the extension's first message reached the bridge") { bridge.received(0).count == 1 }
        #expect(bridge.received(0) == [Data(#"{"hello":"first"}"#.utf8)])

        bridge.send(try NativeMessageFrames.encode(["type": "pairing", "key": "é"]), on: 0)
        try await waitUntil("the extension echoed the bridge's frame") { bridge.received(0).count == 2 }
        let echo = try JSONSerialization.jsonObject(with: bridge.received(0)[1]) as? NSDictionary
        #expect(echo == ["echo": ["type": "pairing", "key": "é"]])

        bridge.close(0)
        try await waitUntil("the extension connected again") { bridge.received(1).count == 1 }
        #expect(bridge.received(1) == [Data(#"{"hello":"again"}"#.utf8)])
        try await waitUntil("only the new port is relayed") { host.nativeMessaging.openPortCount == 1 }
    }

    // MARK: Helpers

    static func application(port: UInt16, wait: Duration = .seconds(3)) -> NativeApplication {
        NativeApplication(applicationIdentifier: "app.safira.test", extensionIdentifier: fixtureID,
                          bundleIdentifier: "app.safira.test.mac", port: port, launchWait: wait)
    }

    /// Connects natively once its worker starts, echoes what it receives, and connects once more when disconnected.
    static func nativeExtension() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "safira-native-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = [
            "manifest.json": """
                {
                  "manifest_version": 3,
                  "name": "Safira native fixture",
                  "description": "Talks to a native app.",
                  "version": "1.0",
                  "key": "c2FmaXJhLXRlc3Qta2V5",
                  "permissions": ["nativeMessaging"],
                  "background": { "service_worker": "background.js", "type": "module" }
                }
                """,
            "background.js": """
                function open(tag) {
                  const port = browser.runtime.connectNative("app.safira.test");
                  port.onMessage.addListener((message) => port.postMessage({ echo: message }));
                  port.onDisconnect.addListener(() => { if (tag === "first") open("again"); });
                  port.postMessage({ hello: tag });
                }
                open("first");
                """,
        ]
        for (name, text) in files {
            try Data(text.utf8).write(to: folder.appending(path: name))
        }
        return folder
    }
}

/// The extension's end of a port, as the relay sees it.
@MainActor
final class FakePort: NativeMessagePort {
    let applicationIdentifier: String?
    private(set) var received: [Any] = []
    private(set) var isDisconnected = false
    private var messageHandler: (@MainActor (Any?) -> Void)?
    private var disconnectHandler: (@MainActor () -> Void)?

    init(_ applicationIdentifier: String?) {
        self.applicationIdentifier = applicationIdentifier
    }

    func onMessage(_ handler: @escaping @MainActor (Any?) -> Void) { messageHandler = handler }
    func onDisconnect(_ handler: @escaping @MainActor () -> Void) { disconnectHandler = handler }
    func send(_ message: Any) { received.append(message) }
    func disconnect() { isDisconnected = true }

    func post(_ message: Any) { messageHandler?(message) }

    func disconnectFromExtension() {
        isDisconnected = true
        disconnectHandler?()
    }
}

/// A stand-in for Verrou's bridge on a random loopback port: it records the frame bodies of each connection, in the
/// order connections arrive, and sends what a test tells it to.
final class FakeBridge: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake-bridge")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var bodies: [[Data]] = []
    private var ended: [Bool] = []
    private let answer: [String: String]?
    let port: UInt16

    private init(listener: NWListener, port: UInt16, answer: [String: String]?) {
        self.listener = listener
        self.port = port
        self.answer = answer
    }

    /// A port nothing listens on: taken from the system, then released.
    static func unusedPort() async throws -> UInt16 {
        let bridge = try await start()
        bridge.stop()
        return bridge.port
    }

    /// - Parameter answer: sent back after the first frame of each connection, as a one-time message expects.
    static func start(port: UInt16 = 0, answer: [String: String]? = nil) async throws -> FakeBridge {
        signal(SIGPIPE, SIG_IGN)
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
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
        let holder = Holder()
        listener.newConnectionHandler = { holder.bridge?.accept($0) }
        listener.start(queue: .global())
        var iterator = ready.makeAsyncIterator()
        let bridge = FakeBridge(listener: listener, port: try await iterator.next() ?? 0, answer: answer)
        holder.bridge = bridge
        return bridge
    }

    private final class Holder: @unchecked Sendable {
        weak var bridge: FakeBridge?
    }

    func received(_ connection: Int) -> [Data] {
        lock.withLock { connection < bodies.count ? bodies[connection] : [] }
    }

    func hasEnded(_ connection: Int) -> Bool {
        lock.withLock { connection < ended.count && ended[connection] }
    }

    func send(_ bytes: Data, on connection: Int) {
        lock.withLock { connections[connection] }.send(content: bytes, completion: .idempotent)
    }

    func close(_ connection: Int) {
        lock.withLock { connections[connection] }.cancel()
    }

    func stop() {
        listener.cancel()
        lock.withLock { connections }.forEach { $0.cancel() }
    }

    private func accept(_ connection: NWConnection) {
        let index = lock.withLock {
            connections.append(connection)
            bodies.append([])
            ended.append(false)
            return connections.count - 1
        }
        connection.start(queue: queue)
        read(connection, index, frames: NativeMessageFrames())
    }

    private func read(_ connection: NWConnection, _ index: Int, frames: NativeMessageFrames) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            var frames = frames
            let new = (try? frames.append(data ?? Data())) ?? []
            let isFirst = lock.withLock {
                let first = bodies[index].isEmpty && !new.isEmpty
                bodies[index] += new
                if isComplete || error != nil { ended[index] = true }
                return first
            }
            if isFirst, let answer, let frame = try? NativeMessageFrames.encode(answer) {
                connection.send(content: frame, completion: .idempotent)
            }
            if !(isComplete || error != nil) { read(connection, index, frames: frames) }
        }
    }
}
