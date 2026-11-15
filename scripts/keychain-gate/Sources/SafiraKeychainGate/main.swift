// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

// Run by scripts/keychain-gate.sh only, signed with Developer ID under a throwaway bundle id. One Profile with a fixed
// identifier, so that its data store and its extensions' state survive the relaunch; Verrou and the probe extension
// are read from the app's own Resources, which the sandbox lets it read. Prints one `RESULT:` line and exits.
//   write: loads Verrou and the probe; the probe's service worker stores a non-extractable CryptoKey in IndexedDB.
//   read:  loads them again; the probe's service worker reads the key back and encrypts and decrypts with it.
//   load:  only loads them, into a Profile whose data store and extension state stay in memory: nothing is stored.
//   native: loads the probe alone, in memory, and has its service worker connect to the native messaging host named in
//          its native.json, registered in Safira's own hosts folder; prints the host's first answer.

import AppKit
import WebKit
import SafiraCore
import SafiraWeb

let mode = CommandLine.arguments.dropFirst().first ?? ""
let profile = ProfileID(rawValue: UUID(uuidString: "6A7E0000-0000-4000-8000-00000000CA7E")!)

@MainActor
func gate() async -> String {
    guard ["write", "read", "load", "native"].contains(mode), let resources = Bundle.main.resourceURL else {
        return "usage: SafiraKeychainGate write|read|load|native"
    }
    let web = ProfileWebContext(profileID: profile, storage: ["load", "native"].contains(mode) ? .inMemory : .onDisk)
    guard let host = web.extensions else { return "the Profile has no extension host" }
    // The host refers to its Profile without keeping it.
    defer { withExtendedLifetime(web) {} }
    if mode == "native" { return await native(host, resources) }
    do {
        let verrou = try await host.loadUnpacked(at: resources.appending(path: "verrou", directoryHint: .isDirectory))
        guard verrou.errors.isEmpty else { return "Verrou loaded with errors: \(verrou.errors)" }
        print("OK: Verrou \(verrou.version) loaded, id \(verrou.identifier)")
        let probe = try await host.loadUnpacked(at: resources.appending(path: "probe", directoryHint: .isDirectory))
        guard probe.errors.isEmpty else { return "the probe loaded with errors: \(probe.errors)" }
        print("OK: the probe loaded, id \(probe.identifier)")
        if mode == "load" { return "loaded" }
        guard let answer = try await ask(host, probe, mode) else {
            return "no answer from the service worker in 30 s (a keychain prompt, or the worker hung)"
        }
        return answer
    } catch {
        return "error: \(error)"
    }
}

/// Opens the probe's gate.html#<operation>, which asks its service worker, and waits for the answer it writes back.
/// An extension's pages load only in its own web view configuration, not in a Tab's.
@MainActor
func ask(_ host: ExtensionHost, _ probe: LoadedExtension, _ operation: String) async throws -> String? {
    guard let configuration = host.webViewConfiguration(forExtension: probe.identifier) else { return nil }
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.load(URLRequest(url: URL(string: "webkit-extension://\(probe.identifier)/gate.html#\(operation)")!))
    let deadline = ContinuousClock.now + .seconds(30)
    while ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(250))
        let answer = try? await webView.callAsyncJavaScript(
            "return document.documentElement.dataset.gate ?? null", contentWorld: .page) as? String
        if let answer { return answer }
    }
    return nil
}

/// Whether the sandbox lets the app read a path: EPERM when it denies it.
func sandboxReads(_ url: URL) -> String {
    var info = stat()
    guard stat(url.path(percentEncoded: false), &info) != 0 else { return "readable" }
    return errno == ENOENT ? "allowed (missing)" : errno == EPERM ? "denied" : "errno \(errno)"
}

@MainActor
func native(_ host: ExtensionHost, _ resources: URL) async -> String {
    let hosts = NativeMessaging.hostsFolder
    print("OK: sandbox, \(hosts.path(percentEncoded: false)): \(sandboxReads(hosts))")
    do {
        let probe = try await host.loadUnpacked(at: resources.appending(path: "probe", directoryHint: .isDirectory))
        print("OK: the probe loaded, id \(probe.identifier)")
        guard let answer = try await ask(host, probe, "native") else { return "no answer from the native host in 30 s" }
        return "native \(answer)"
    } catch {
        return "error: \(error)"
    }
}

NSApplication.shared.setActivationPolicy(.prohibited)
Task { @MainActor in
    let result = await gate()
    print("RESULT: \(result)")
    fflush(stdout)
    exit(["written", "read back", "loaded"].contains(result) || result.hasPrefix("native {") ? 0 : 1)
}
NSApplication.shared.run()
