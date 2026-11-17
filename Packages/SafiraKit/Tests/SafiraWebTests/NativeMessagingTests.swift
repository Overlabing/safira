// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Foundation
@testable import SafiraWeb
import TestSupport
import Testing
import WebKit

/// Native messaging through host manifests, as Chrome does it, with an echo host written for these tests in a
/// temporary manifests folder.
@MainActor
@Suite(.serialized, .oneWebKitTestAtATime) struct NativeMessagingTests {
    nonisolated static let fixtureID = "pfikphmpnbnmihdgfbljkjgfnamcpjme"

    // MARK: Framing

    @Test func aFrameIsALittleEndianLengthThenTheJSON() throws {
        let frame = try NativeMessageFrames.encode(["type": "pairing", "name": "Safira é"])
        #expect(Array(frame.prefix(4)) == [37, 0, 0, 0])
        #expect(frame.dropFirst(4) == Data(#"{"name":"Safira é","type":"pairing"}"#.utf8))
    }

    @Test func framesSplitAcrossReadsComeOutWholeAndInOrder() throws {
        var frames = NativeMessageFrames()
        let bytes = try NativeMessageFrames.encode(["n": 1]) + NativeMessageFrames.encode(["n": 2])
        #expect(try frames.append(bytes.prefix(3)) == [])
        #expect(try frames.append(bytes.dropFirst(3).prefix(8)) == [Data(#"{"n":1}"#.utf8)])
        #expect(try frames.append(bytes.dropFirst(11)) == [Data(#"{"n":2}"#.utf8)])
    }

    @Test func aHostMessageOverOneMegabyteOrEmptyIsRefused() {
        var empty = NativeMessageFrames()
        #expect(throws: NativeMessageFrames.Invalid(length: 0)) { try empty.append(Data([0, 0, 0, 0])) }
        var oversized = NativeMessageFrames()
        #expect(throws: NativeMessageFrames.Invalid(length: 1_048_577)) { try oversized.append(Data([1, 0, 16, 0])) }
    }

    // MARK: Manifests

    @Test func theHostsFolderIsSafirasInTheUsersRealHome() {
        #expect(NativeMessaging.hostsFolder.path(percentEncoded: false)
            .hasSuffix("/Library/Application Support/Safira/NativeMessagingHosts/"))
        #expect(!NativeMessaging.hostsFolder.path(percentEncoded: false).contains("/Library/Containers/"))
    }

    @Test func hostNamesFollowChromesRules() {
        #expect(NativeMessaging.isValidName("com.example.host_1"))
        for name in ["", ".a", "a.", "a..b", "A.b", "a/b", "../a", "a-b"] {
            #expect(!NativeMessaging.isValidName(name), "\(name)")
        }
    }

    @Test func aMissingOrMalformedManifestIsHostNotFound() throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        let messaging = NativeMessaging(folder: hosts.folder)
        #expect(throws: NativeMessagingError.hostNotFound) { try messaging.manifest("com.missing", allowing: Self.fixtureID) }
        #expect(throws: NativeMessagingError.hostNotFound) { try messaging.manifest(nil, allowing: Self.fixtureID) }
        try hosts.write(["name": "com.other.name", "path": hosts.script.path, "type": "stdio",
                         "allowed_origins": [NativeMessaging.origin(Self.fixtureID)]], as: "com.renamed")
        #expect(throws: NativeMessagingError.hostNotFound) { try messaging.manifest("com.renamed", allowing: Self.fixtureID) }
        try hosts.write(["name": "com.relative", "path": "echo.py", "type": "stdio",
                         "allowed_origins": [NativeMessaging.origin(Self.fixtureID)]], as: "com.relative")
        #expect(throws: NativeMessagingError.hostNotFound) { try messaging.manifest("com.relative", allowing: Self.fixtureID) }
    }

    @Test func anExtensionNotInAllowedOriginsIsForbidden() async throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        let messaging = NativeMessaging(folder: hosts.folder)
        let port = FakePort(EchoHosts.name)
        #expect(throws: NativeMessagingError.forbidden) {
            try messaging.connect(port, extensionIdentifier: "abcdefghijklmnopabcdefghijklmnop")
        }
        await #expect(throws: NativeMessagingError.forbidden) {
            try await messaging.sendMessage(["n": 1], applicationIdentifier: EchoHosts.name,
                                            extensionIdentifier: "abcdefghijklmnopabcdefghijklmnop")
        }
        #expect(messaging.openPortCount == 0)
        #expect(hosts.received().isEmpty)
    }

    // MARK: Ports

    @Test func aPortTalksToItsHostInFramesAndTheHostGetsTheOriginAsArgument() async throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        let messaging = NativeMessaging(folder: hosts.folder)
        let port = FakePort(EchoHosts.name)
        try messaging.connect(port, extensionIdentifier: Self.fixtureID)

        port.post(["type": "pair", "name": "Safira — Work"])
        port.post(["n": 2])
        try await waitUntil("the host echoed both messages") { port.received.count == 2 }
        let first = try #require(port.received.first as? [String: Any])
        #expect(first["echo"] as? NSDictionary == ["type": "pair", "name": "Safira — Work"])
        #expect(first["args"] as? [String] == ["chrome-extension://pfikphmpnbnmihdgfbljkjgfnamcpjme/"])
        #expect((first["cwd"] as? String).map { URL(filePath: $0).resolvingSymlinksInPath().path() }
            == URL(filePath: hosts.folder.path(), directoryHint: .notDirectory).resolvingSymlinksInPath().path())
        #expect((port.received.last as? [String: Any])?["echo"] as? NSDictionary == ["n": 2])
        #expect(hosts.received() == [#"{"name":"Safira — Work","type":"pair"}"#, #"{"n":2}"#])
        #expect(!port.isDisconnected)
    }

    @Test func closingThePortEndsTheHostProcess() async throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        let messaging = NativeMessaging(folder: hosts.folder)
        let port = FakePort(EchoHosts.name)
        try messaging.connect(port, extensionIdentifier: Self.fixtureID)
        port.post(["n": 1])
        try await waitUntil("the host answered") { port.received.count == 1 }
        let pid = try #require((port.received.first as? [String: Any])?["pid"] as? Int32)
        #expect(kill(pid, 0) == 0)

        port.disconnectFromExtension()
        #expect(messaging.openPortCount == 0)
        try await waitUntil("the host process ended") { kill(pid, 0) != 0 }
    }

    @Test func whenTheHostExitsThePortIsDisconnectedWithChromesErrorAndANewPortStartsAnotherHost() async throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        let messaging = NativeMessaging(folder: hosts.folder)
        let first = FakePort(EchoHosts.name)
        try messaging.connect(first, extensionIdentifier: Self.fixtureID)
        first.post(["exit": 3])
        try await waitUntil("the port was disconnected") { first.isDisconnected }
        #expect(first.disconnectError == "Native host has exited.")
        #expect(messaging.openPortCount == 0)

        let second = FakePort(EchoHosts.name)
        try messaging.connect(second, extensionIdentifier: Self.fixtureID)
        second.post(["n": 2])
        try await waitUntil("a second host answered") { second.received.count == 1 }
        #expect(!second.isDisconnected)
    }

    @Test func aHostMessageOverTheLimitEndsTheConnection() async throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        let messaging = NativeMessaging(folder: hosts.folder)
        let port = FakePort(EchoHosts.name)
        try messaging.connect(port, extensionIdentifier: Self.fixtureID)
        port.post(["oversized": true])
        try await waitUntil("the port was disconnected") { port.isDisconnected }
        #expect(port.received.isEmpty)
        #expect(port.disconnectError == "Error when communicating with the native messaging host.")
    }

    @Test func aHostThatCannotStartIsHostNotFound() throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        try hosts.write(["name": "com.gone", "path": hosts.folder.appending(path: "gone").path, "type": "stdio",
                         "allowed_origins": [NativeMessaging.origin(Self.fixtureID)]], as: "com.gone")
        let messaging = NativeMessaging(folder: hosts.folder)
        #expect(throws: NativeMessagingError.hostNotFound) {
            try messaging.connect(FakePort("com.gone"), extensionIdentifier: Self.fixtureID)
        }
        #expect(messaging.openPortCount == 0)
    }

    /// macOS kills a sandboxed child that asks for its own sandbox; Safira refuses to start it and says why.
    @Test func aHostSandboxedOnItsOwnIsRefusedBeforeItStarts() throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        let sandboxed = try hosts.signedCopyOfTrue(named: "sandboxed", entitlements: ["com.apple.security.app-sandbox": true])
        let inheriting = try hosts.signedCopyOfTrue(named: "inheriting", entitlements: [
            "com.apple.security.app-sandbox": true, "com.apple.security.inherit": true,
        ])
        #expect(NativeHostSignature.needsItsOwnSandbox(sandboxed.path))
        #expect(!NativeHostSignature.needsItsOwnSandbox(inheriting.path))
        #expect(!NativeHostSignature.needsItsOwnSandbox(hosts.script.path))
        #expect(!NativeHostSignature.needsItsOwnSandbox("/usr/bin/true"))

        try hosts.write(["name": "com.sandboxed", "path": sandboxed.path, "type": "stdio",
                         "allowed_origins": [NativeMessaging.origin(Self.fixtureID)]], as: "com.sandboxed")
        let messaging = NativeMessaging(folder: hosts.folder)
        #expect(throws: NativeMessagingError.hostSandboxed(name: "com.sandboxed")) {
            try messaging.connect(FakePort("com.sandboxed"), extensionIdentifier: Self.fixtureID)
        }
        #expect(NativeMessagingError.hostSandboxed(name: "com.sandboxed").localizedDescription
            == "Native messaging host com.sandboxed is sandboxed without com.apple.security.inherit, so macOS would stop it at launch.")
    }

    @Test func aOneTimeMessageGetsTheHostsFirstMessage() async throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        let messaging = NativeMessaging(folder: hosts.folder)
        let reply = try await messaging.sendMessage(["type": "request"], applicationIdentifier: EchoHosts.name,
                                                    extensionIdentifier: Self.fixtureID)
        #expect((reply as? [String: Any])?["echo"] as? NSDictionary == ["type": "request"])
        await #expect(throws: NativeMessagingError.hostNotFound) {
            try await messaging.sendMessage(["n": 1], applicationIdentifier: "com.missing",
                                            extensionIdentifier: Self.fixtureID)
        }
    }

    // MARK: Through WebKit

    /// A real extension's `connectNative` port: framed both ways, disconnected when the host exits, and a new host for
    /// the port the extension opens next.
    @Test func anExtensionsPortReachesItsHostAndReconnectsAfterTheHostExits() async throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        let folder = try Self.nativeExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = try ExtensionHostTests.profile()
        let host = try #require(profile.extensions)
        host.nativeMessaging = NativeMessaging(folder: hosts.folder)
        try await host.loadUnpacked(at: folder)
        try await ExtensionHostTests.loadBackgroundContent(of: profile)

        try await waitUntil("the second host heard from the extension") { hosts.received().count == 4 }
        let received = hosts.received()
        #expect(received.first == #"{"hello":"first"}"#)
        #expect(received[1] == #"{"args":["chrome-extension://pfikphmpnbnmihdgfbljkjgfnamcpjme/"],"got":{"hello":"first"}}"#)
        #expect(received[2] == #"{"exit":0}"#)
        // WebKit (macOS 27) does not hand the app's disconnect error to `onDisconnect`; the error Safira gives is checked
        // on the port, in whenTheHostExits….
        #expect(received[3] == #"{"after":"none","hello":"again"}"#)
        try await waitUntil("only the new port is open") { host.nativeMessaging.openPortCount == 1 }
    }

    // MARK: A real host

    /// Verrou's own host, registered through a temporary manifest only: an unpaired request reaches Verrou, which answers
    /// `unknown_client` and shows nothing. Needs Verrou installed and running, so not in CI.
    @Test(.enabled(if: RealHost.isAvailable, "needs Verrou installed and running"))
    func aRealHostRegisteredByManifestAnswersThroughThePort() async throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        try hosts.write(RealHost.manifest, as: RealHost.name)
        let messaging = NativeMessaging(folder: hosts.folder)
        let port = FakePort(RealHost.name)
        try messaging.connect(port, extensionIdentifier: RealHost.extensionID)
        port.post(["type": "request", "client": "safira-host-check", "iv": "AAAAAAAAAAAAAAAA", "data": "AAAA"])
        try await waitUntil("the host answered") { !port.received.isEmpty }
        #expect(port.received.first as? NSDictionary == ["type": "error", "code": "unknown_client"])
        port.disconnectFromExtension()
    }

    /// The same host behind Verrou's popup: "Not linked", then the pairing code after Link. Verrou shows its own Link
    /// window in front, so this runs only with `SAFIRA_PAIRING_CHECK=1` and someone at the Mac, who answers Decline.
    /// `SAFIRA_CAPTURE_DIR` receives the popup's two pictures.
    @Test(.enabled(if: RealHost.isAvailable && ProcessInfo.processInfo.environment["SAFIRA_PAIRING_CHECK"] == "1"
                   && ExtensionHostTests.verrouFolder != nil, "needs SAFIRA_PAIRING_CHECK=1 and Verrou running"))
    func aRealExtensionsPopupReachesThePairingCodeThroughItsHost() async throws {
        let hosts = try EchoHosts()
        defer { hosts.remove() }
        try hosts.write(RealHost.manifest, as: RealHost.name)
        let original = try #require(ExtensionHostTests.verrouFolder)
        let copy = FileManager.default.temporaryDirectory.appending(path: "safira-verrou-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: original, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let profile = try ExtensionHostTests.profile()
        let host = try #require(profile.extensions)
        host.nativeMessaging = NativeMessaging(folder: hosts.folder)
        let loaded = try await host.loadUnpacked(at: copy)
        try await ExtensionHostTests.loadBackgroundContent(of: profile)
        let popups = ExtensionActionTests.PopupRecorder(host: host)

        host.performAction(extensionID: loaded.identifier)
        try await waitUntil("the popup was presented") { popups.presented.count == 1 }
        let webView = try #require(popups.presented.first?.action.popupWebView)
        let window = TestWindow.host(webView, width: 360, height: 300)
        defer { window.close() }
        try await waitUntilAsync("the popup shows it is not linked") {
            await ExtensionActionTests.evaluate("document.getElementById('state')?.textContent ?? ''", in: webView)
                == "Not linked"
        }
        try await Self.capture(webView, as: "popup-not-linked.png")
        _ = await ExtensionActionTests.evaluate("(document.querySelector('#main button')?.click(), '')", in: webView)
        try await waitUntilAsync("the popup shows the pairing code") {
            let code = await ExtensionActionTests.evaluate("document.querySelector('.code')?.textContent ?? ''", in: webView)
            return code?.contains(/^\d{3} ?\d{3}$/) == true
        }
        try await Self.capture(webView, as: "popup-pairing-code.png")
        #expect(host.nativeMessaging.openPortCount == 1)
    }

    // MARK: Helpers

    static func capture(_ webView: WKWebView, as name: String) async throws {
        guard let folder = ProcessInfo.processInfo.environment["SAFIRA_CAPTURE_DIR"] else { return }
        try await Task.sleep(for: .milliseconds(300))
        let image = try await webView.takeSnapshot(configuration: nil)
        let bitmap = image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
        let png = try #require(bitmap?.representation(using: .png, properties: [:]))
        try png.write(to: URL(filePath: folder, directoryHint: .isDirectory).appending(path: name))
    }

    /// Connects once its worker starts, reports the echo, asks the host to exit, then connects again with the error.
    static func nativeExtension() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "safira-native-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = [
            "manifest.json": """
                {
                  "manifest_version": 3,
                  "name": "Safira native fixture",
                  "description": "Talks to a native host.",
                  "version": "1.0",
                  "key": "c2FmaXJhLXRlc3Qta2V5",
                  "permissions": ["nativeMessaging"],
                  "background": { "service_worker": "background.js", "type": "module" }
                }
                """,
            "background.js": """
                const port = browser.runtime.connectNative("\(EchoHosts.name)");
                port.onMessage.addListener((message) => {
                  if (message.echo?.hello !== "first") return;
                  port.postMessage({ got: message.echo, args: message.args });
                  port.postMessage({ exit: 0 });
                });
                port.onDisconnect.addListener((closed) => {
                  const after = closed?.error?.message ?? browser.runtime.lastError?.message ?? "none";
                  browser.runtime.connectNative("\(EchoHosts.name)").postMessage({ hello: "again", after });
                });
                port.postMessage({ hello: "first" });
                """,
        ]
        for (name, text) in files {
            try Data(text.utf8).write(to: folder.appending(path: name))
        }
        return folder
    }
}

/// A temporary manifests folder with an echo host: it answers each message with `{echo, args, pid, cwd}`, exits on
/// `{"exit": n}`, sends a frame over the limit on `{"oversized": true}`, and logs every message it reads.
struct EchoHosts {
    static let name = "com.overlabing.safira.echo"
    let folder: URL
    var script: URL { folder.appending(path: "echo.py") }
    private var log: URL { folder.appending(path: "received.log") }

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "safira-hosts-\(UUID().uuidString)",
                                                                  directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(Self.source.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try write(["name": Self.name, "description": "Echo", "path": script.path, "type": "stdio",
                   "allowed_origins": [NativeMessaging.origin(NativeMessagingTests.fixtureID)]], as: Self.name)
    }

    func write(_ manifest: [String: Any], as name: String) throws {
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appending(path: "\(name).json"))
    }

    /// The messages the hosts read, in order, as their JSON text.
    func received() -> [String] {
        ((try? String(contentsOf: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A copy of /usr/bin/true signed ad hoc with these entitlements; it is never run.
    func signedCopyOfTrue(named name: String, entitlements: [String: Bool]) throws -> URL {
        let program = folder.appending(path: name)
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: program)
        let plist = folder.appending(path: "\(name).entitlements")
        try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0).write(to: plist)
        let codesign = Process()
        codesign.executableURL = URL(filePath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", "--entitlements", plist.path, program.path]
        codesign.standardOutput = FileHandle.nullDevice
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        #expect(codesign.terminationStatus == 0)
        return program
    }

    private static let source = #"""
        #!/usr/bin/python3 -I
        import json, os, struct, sys
        log = os.path.join(os.path.dirname(os.path.abspath(__file__)), "received.log")
        def send(body):
            sys.stdout.buffer.write(struct.pack("<I", len(body)) + body)
            sys.stdout.buffer.flush()
        while True:
            header = sys.stdin.buffer.read(4)
            if len(header) < 4:
                break
            body = sys.stdin.buffer.read(struct.unpack("<I", header)[0])
            message = json.loads(body)
            with open(log, "a", encoding="utf-8") as out:
                out.write(json.dumps(message, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n")
            if isinstance(message, dict) and "exit" in message:
                sys.exit(message["exit"])
            if isinstance(message, dict) and message.get("oversized"):
                sys.stdout.buffer.write(struct.pack("<I", 1024 * 1024 + 1))
                sys.stdout.buffer.flush()
                continue
            send(json.dumps({"echo": message, "args": sys.argv[1:], "pid": os.getpid(), "cwd": os.getcwd()}).encode())
        """#
}

/// Verrou's installed host, for the optional real-world checks: registered here through a temporary manifest only.
enum RealHost {
    static let name = "app.verrou.bridge"
    static let path = "/Applications/Verrou.app/Contents/MacOS/verrou-native-host"
    static let extensionID = "pmdlgnpbjfdnmpeadbecmgfoojmocibg"
    static var manifest: [String: Any] { ["name": name, "description": "Verrou", "path": path, "type": "stdio",
                                          "allowed_origins": [NativeMessaging.origin(extensionID)]] }

    nonisolated static var isAvailable: Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(41738).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}

/// The extension's end of a port, as native messaging sees it.
@MainActor
final class FakePort: NativeMessagePort {
    let applicationIdentifier: String?
    private(set) var received: [Any] = []
    private(set) var isDisconnected = false
    private(set) var disconnectError: String?
    private var messageHandler: (@MainActor (Any?) -> Void)?
    private var disconnectHandler: (@MainActor () -> Void)?

    init(_ applicationIdentifier: String?) {
        self.applicationIdentifier = applicationIdentifier
    }

    func onMessage(_ handler: @escaping @MainActor (Any?) -> Void) { messageHandler = handler }
    func onDisconnect(_ handler: @escaping @MainActor () -> Void) { disconnectHandler = handler }
    func send(_ message: Any) { received.append(message) }

    func disconnect(_ error: (any Error)?) {
        isDisconnected = true
        disconnectError = error?.localizedDescription
    }

    func post(_ message: Any) { messageHandler?(message) }

    func disconnectFromExtension() {
        isDisconnected = true
        disconnectHandler?()
    }
}
