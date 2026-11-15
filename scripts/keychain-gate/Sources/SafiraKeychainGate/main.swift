// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

// Run by scripts/keychain-gate.sh only, signed with Developer ID under a throwaway bundle id. One Profile with a fixed
// identifier, so that its data store and its extensions' state survive the relaunch; Verrou and the probe extension
// are read from the app's own Resources, which the sandbox lets it read. Prints one `RESULT:` line and exits.
//   write: loads Verrou and the probe; the probe's service worker stores a non-extractable CryptoKey in IndexedDB.
//   read:  loads them again; the probe's service worker reads the key back and encrypts and decrypts with it.
//   load:  only loads them, into a Profile whose data store and extension state stay in memory: nothing is stored.

import AppKit
import SafiraCore
import SafiraWeb

let mode = CommandLine.arguments.dropFirst().first ?? ""
let profile = ProfileID(rawValue: UUID(uuidString: "6A7E0000-0000-4000-8000-00000000CA7E")!)

@MainActor
func gate() async -> String {
    guard ["write", "read", "load"].contains(mode), let resources = Bundle.main.resourceURL else {
        return "usage: SafiraKeychainGate write|read|load"
    }
    let web = ProfileWebContext(profileID: profile, storage: mode == "load" ? .inMemory : .onDisk)
    guard let host = web.extensions else { return "the Profile has no extension host" }
    do {
        let verrou = try await host.loadUnpacked(at: resources.appending(path: "verrou", directoryHint: .isDirectory))
        guard verrou.errors.isEmpty else { return "Verrou loaded with errors: \(verrou.errors)" }
        print("OK: Verrou \(verrou.version) loaded, id \(verrou.identifier)")
        let probe = try await host.loadUnpacked(at: resources.appending(path: "probe", directoryHint: .isDirectory))
        guard probe.errors.isEmpty else { return "the probe loaded with errors: \(probe.errors)" }
        print("OK: the probe loaded, id \(probe.identifier)")
        if mode == "load" { return "loaded" }
        let page = web.makePage(for: TabID())
        page.load(URL(string: "webkit-extension://\(probe.identifier)/gate.html#\(mode)")!, httpsFirst: false)
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
            let answer = try? await page.webView.callAsyncJavaScript(
                "return document.documentElement.dataset.gate ?? null", contentWorld: .page) as? String
            if let answer { return answer }
        }
        return "no answer from the service worker in 30 s (a keychain prompt, or the worker hung)"
    } catch {
        return "error: \(error)"
    }
}

NSApplication.shared.setActivationPolicy(.prohibited)
Task { @MainActor in
    let result = await gate()
    print("RESULT: \(result)")
    fflush(stdout)
    exit(["written", "read back", "loaded"].contains(result) ? 0 : 1)
}
NSApplication.shared.run()
