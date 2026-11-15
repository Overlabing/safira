// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Darwin
import Foundation
import Security
import WebKit

/// A native messaging host, as an app registers it for Chrome: `<name>.json` in Safira's `NativeMessagingHosts`
/// folder (docs/native-messaging.md, ADR 0007). Safira knows no host in particular; it reads what apps register.
struct NativeMessagingHostManifest: Decodable, Equatable {
    let name: String
    let description: String?
    let path: String
    let type: String
    let allowedOrigins: [String]

    enum CodingKeys: String, CodingKey {
        case name, description, path, type
        case allowedOrigins = "allowed_origins"
    }
}

/// Chrome's errors, word for word: extensions compare them (`runtime.lastError.message`).
public enum NativeMessagingError: LocalizedError, Equatable {
    case hostNotFound
    case forbidden
    case hostExited
    case communication
    /// Not one of Chrome's: a host sandboxed on its own cannot run as Safira's child (docs/native-messaging.md).
    case hostSandboxed(name: String)

    public var errorDescription: String? {
        switch self {
        case .hostNotFound: "Specified native messaging host not found."
        case .forbidden: "Access to the specified native messaging host is forbidden."
        case .hostExited: "Native host has exited."
        case .communication: "Error when communicating with the native messaging host."
        case .hostSandboxed(let name):
            "Native messaging host \(name) is sandboxed without com.apple.security.inherit, so macOS would stop it at launch."
        }
    }
}

/// A host program's own sandbox, read from its code signature before it is started. Safira is sandboxed, and macOS
/// kills at launch a sandboxed child that does not inherit its parent's sandbox (SIGTRAP in `_libsecinit_appsandbox`).
enum NativeHostSignature {
    /// True when the program at `path` asks for its own sandbox without `com.apple.security.inherit`. An unsigned
    /// program or a script has no entitlements, so it can start.
    static func needsItsOwnSandbox(_ path: String) -> Bool {
        let entitlements = self.entitlements(path)
        return entitlements["com.apple.security.app-sandbox"] as? Bool == true
            && entitlements["com.apple.security.inherit"] as? Bool != true
    }

    static func entitlements(_ path: String) -> [String: Any] {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(filePath: path) as CFURL, [], &code) == errSecSuccess, let code else {
            return [:]
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
              let information = information as? [String: Any]
        else { return [:] }
        return information[kSecCodeInfoEntitlementsDict as String] as? [String: Any] ?? [:]
    }
}

/// Native Messaging framing: a 4-byte little-endian length, then that many bytes of UTF-8 JSON.
struct NativeMessageFrames {
    /// The largest message a host may send (Chrome's limit); a longer one ends the connection.
    static let maximumFromHost = 1024 * 1024
    /// The largest message sent to a host (Chrome's limit).
    static let maximumToHost = 64 * 1024 * 1024

    struct Invalid: Error, Equatable {
        let length: Int
    }

    private var buffer = Data()

    static func encode(_ message: Any) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: message,
                                              options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
        guard !body.isEmpty, body.count <= maximumToHost else { throw Invalid(length: body.count) }
        var length = UInt32(body.count).littleEndian
        return Data(bytes: &length, count: 4) + body
    }

    static func decode(_ body: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed])
    }

    /// Adds bytes the host wrote and returns the bodies of the frames now complete, in order.
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var bodies: [Data] = []
        while buffer.count >= 4 {
            let start = buffer.startIndex
            let length = buffer[start..<start + 4].reversed().reduce(0) { $0 << 8 | Int($1) }
            guard length > 0, length <= Self.maximumFromHost else { throw Invalid(length: length) }
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
    func disconnect(_ error: (any Error)?)
}

/// `runtime.connectNative` and `runtime.sendNativeMessage`, the way Chrome implements them on macOS: the host named by
/// the extension is looked up in the manifests folder, refused unless the extension's origin is in its
/// `allowed_origins`, and started with that origin as its argument. Messages go through its stdin and stdout, framed.
/// One process per port, ended when the port closes; Safira never reads what passes.
@MainActor
public final class NativeMessaging {
    /// `~/Library/Application Support/Safira/NativeMessagingHosts`, in the user's real home: the sandbox's home is the
    /// app's container, and the entitlements open this one folder for reading.
    public nonisolated static var hostsFolder: URL {
        let home = getpwuid(getuid())?.pointee.pw_dir.map { String(cString: $0) } ?? NSHomeDirectory()
        return URL(filePath: home, directoryHint: .isDirectory)
            .appending(path: "Library/Application Support/Safira/NativeMessagingHosts", directoryHint: .isDirectory)
    }

    private let folder: URL
    private var connections: [ObjectIdentifier: NativeHostConnection] = [:]

    /// - Parameter folder: where the manifests are read; another folder than Safira's is for tests and checks only.
    public init(folder: URL = NativeMessaging.hostsFolder) {
        self.folder = folder
    }

    /// The ports currently connected to a host.
    var openPortCount: Int { connections.count }

    /// Starts the host for `port`, or throws Chrome's error when it is missing or refuses this extension.
    func connect(_ port: any NativeMessagePort, extensionIdentifier: String) throws {
        let manifest = try self.manifest(port.applicationIdentifier, allowing: extensionIdentifier)
        let key = ObjectIdentifier(port)
        let connection = NativeHostConnection(port: port) { [weak self] in self?.connections[key] = nil }
        connections[key] = connection
        do {
            try connection.start(manifest, origin: Self.origin(extensionIdentifier))
        } catch {
            connections[key] = nil
            throw error
        }
    }

    /// A one-time message: a new host process gets it, and its first message is the reply.
    func sendMessage(_ message: Any, applicationIdentifier: String?, extensionIdentifier: String) async throws -> Any {
        let manifest = try self.manifest(applicationIdentifier, allowing: extensionIdentifier)
        let frame = try NativeMessageFrames.encode(message)
        let process = NativeHostProcess(manifest, origin: Self.origin(extensionIdentifier))
        defer { process.stop() }
        let body = try await withCheckedThrowingContinuation { (done: CheckedContinuation<Data, any Error>) in
            let answer = FirstAnswer(done)
            do {
                try process.start { answer.give(.success($0)) } onEnd: { answer.give(.failure($0)) }
                process.write(frame)
            } catch {
                answer.give(.failure(error))
            }
        }
        return try NativeMessageFrames.decode(body)
    }

    nonisolated static func origin(_ extensionIdentifier: String) -> String {
        "chrome-extension://\(extensionIdentifier)/"
    }

    /// Chrome's rules: a name of lowercase letters, digits, `_` and `.`, not starting, ending or doubling a dot; a
    /// manifest of type `stdio` that carries the same name and an absolute path, and lists the origin exactly.
    func manifest(_ name: String?, allowing extensionIdentifier: String) throws -> NativeMessagingHostManifest {
        guard let name, Self.isValidName(name) else { throw NativeMessagingError.hostNotFound }
        guard let data = try? Data(contentsOf: folder.appending(path: "\(name).json")),
              let manifest = try? JSONDecoder().decode(NativeMessagingHostManifest.self, from: data),
              manifest.name == name, manifest.type == "stdio", manifest.path.hasPrefix("/")
        else { throw NativeMessagingError.hostNotFound }
        guard manifest.allowedOrigins.contains(Self.origin(extensionIdentifier)) else {
            throw NativeMessagingError.forbidden
        }
        guard !NativeHostSignature.needsItsOwnSandbox(manifest.path) else {
            throw NativeMessagingError.hostSandboxed(name: name)
        }
        return manifest
    }

    nonisolated static func isValidName(_ name: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")
        return !name.isEmpty && name.allSatisfy(allowed.contains) && !name.hasPrefix(".") && !name.hasSuffix(".")
            && !name.contains("..")
    }
}

/// One port and its host process: what the extension posts goes to the host's stdin, each frame the host writes goes
/// back to the port. Either end closing closes the other.
@MainActor
final class NativeHostConnection {
    private let port: any NativeMessagePort
    private let onClose: @MainActor () -> Void
    private var process: NativeHostProcess?
    private var isClosed = false

    init(port: any NativeMessagePort, onClose: @escaping @MainActor () -> Void) {
        self.port = port
        self.onClose = onClose
    }

    func start(_ manifest: NativeMessagingHostManifest, origin: String) throws {
        let process = NativeHostProcess(manifest, origin: origin)
        try process.start { [weak self] body in
            guard let self else { return }
            guard let message = try? NativeMessageFrames.decode(body) else {
                return close(NativeMessagingError.communication)
            }
            port.send(message)
        } onEnd: { [weak self] error in
            self?.close(error)
        }
        self.process = process
        port.onMessage { [weak self] message in self?.forward(message) }
        port.onDisconnect { [weak self] in self?.close(nil, disconnectingPort: false) }
    }

    private func forward(_ message: Any?) {
        guard !isClosed else { return }
        guard let message, let frame = try? NativeMessageFrames.encode(message) else {
            return close(NativeMessagingError.communication)
        }
        process?.write(frame)
    }

    private func close(_ error: (any Error)?, disconnectingPort: Bool = true) {
        guard !isClosed else { return }
        isClosed = true
        process?.stop()
        process = nil
        if disconnectingPort { port.disconnect(error) }
        onClose()
    }
}

/// A host process started as Chrome starts one: its path, the caller's origin as argument, its own folder as working
/// directory, stderr left to the system. It inherits Safira's sandbox.
@MainActor
final class NativeHostProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    /// Writes may wait for the host to read: they happen off the main thread, in order.
    private let writes = DispatchQueue(label: "native-messaging.write")
    private var frames = NativeMessageFrames()
    private var onEnd: (@MainActor (NativeMessagingError) -> Void)?

    init(_ manifest: NativeMessagingHostManifest, origin: String) {
        let path = URL(filePath: manifest.path)
        process.executableURL = path
        process.arguments = [origin]
        process.currentDirectoryURL = path.deletingLastPathComponent()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
    }

    func start(_ onBody: @escaping @MainActor (Data) -> Void,
               onEnd: @escaping @MainActor (NativeMessagingError) -> Void) throws {
        self.onEnd = onEnd
        // A host that has exited would otherwise kill Safira with SIGPIPE on the next write.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // The main queue, not a Task: the host's bytes must reach the parser in the order they were read.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.read(data, onBody) }
            }
        }
        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            throw NativeMessagingError.hostNotFound
        }
    }

    func write(_ frame: Data) {
        let handle = input.fileHandleForWriting
        writes.async {
            try? handle.write(contentsOf: frame)
        }
    }

    /// Closes the host's stdin, which tells it to exit, and ends it if it is still running a moment later.
    func stop() {
        onEnd = nil
        output.fileHandleForReading.readabilityHandler = nil
        let handle = input.fileHandleForWriting
        let process = process
        writes.async {
            try? handle.close()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { process.terminate() }
            }
        }
    }

    private func read(_ data: Data, _ onBody: @MainActor (Data) -> Void) {
        guard onEnd != nil else { return }
        guard !data.isEmpty else { return end(.hostExited) }
        do {
            for body in try frames.append(data) {
                onBody(body)
                guard onEnd != nil else { return }
            }
        } catch {
            end(.communication)
        }
    }

    private func end(_ error: NativeMessagingError) {
        let onEnd = onEnd
        stop()
        onEnd?(error)
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

/// WebKit disconnects a port it no longer sees retained, so the connection keeps it.
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

    func disconnect(_ error: (any Error)?) {
        port.disconnect(throwing: error)
    }
}
