// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Foundation
import Network
@testable import SafiraWeb
import TestSupport
import Testing
import WebKit

/// The relay against the real Verrou running on this Mac: skipped where Verrou's bridge does not listen (CI). Nothing
/// here pairs, so no key is created on either side.
@MainActor
@Suite(.serialized) struct VerrouBridgeTests {
    nonisolated static var bridgeListens: Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = NativeApplication.verrou.port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    /// Where `SAFIRA_CAPTURE_DIR` points, to keep the popup's pictures; the captures run only when it is set.
    nonisolated static var captureFolder: URL? {
        ProcessInfo.processInfo.environment["SAFIRA_CAPTURE_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
    }

    /// Asks a pairing of Verrou, which shows Verrou's own "Link?" window in front: only when someone at the Mac set
    /// `SAFIRA_VERROU_PAIRING_CHECK=1`, and they answer Decline there (Return declines).
    nonisolated static var pairingCheck: Bool {
        ProcessInfo.processInfo.environment["SAFIRA_VERROU_PAIRING_CHECK"] == "1"
    }

    /// An unpaired request goes through the relay, framed, to Verrou's bridge, which answers `unknown_client` and
    /// shows nothing: the same answer Verrou's own native host gets.
    @Test(.enabled(if: VerrouBridgeTests.bridgeListens, "needs Verrou running"))
    func theRealBridgeAnswersARelayedRequestFromAnUnknownClient() async throws {
        let verrou = NativeApplication.verrou
        let application = NativeApplication(applicationIdentifier: verrou.applicationIdentifier,
                                            extensionIdentifier: NativeMessagingRelayTests.fixtureID,
                                            bundleIdentifier: verrou.bundleIdentifier, port: verrou.port)
        let relay = NativeMessagingRelay(applications: [application]) { _ in
            Issue.record("Verrou's bridge listens: nothing should be launched")
        }
        let port = FakePort(verrou.applicationIdentifier)
        try relay.connect(port, extensionIdentifier: NativeMessagingRelayTests.fixtureID)
        port.post(["type": "request", "client": "safira-relay-check", "iv": "AAAAAAAAAAAAAAAA", "data": "AAAA"])

        try await waitUntil("Verrou's bridge answered") { !port.received.isEmpty }
        #expect(port.received.first as? NSDictionary == ["type": "error", "code": "unknown_client"])
        port.disconnectFromExtension()
        #expect(relay.openPortCount == 0)
    }

    /// Verrou's popup in a Profile, through the real relay: "Not linked" first, then, after Link, the pairing code
    /// that Verrou shows too. The pairing is left unanswered here; declining it in Verrou ends it.
    @Test(.enabled(if: VerrouBridgeTests.pairingCheck && VerrouBridgeTests.bridgeListens
                   && ExtensionHostTests.verrouFolder != nil && VerrouBridgeTests.captureFolder != nil,
                   "needs SAFIRA_VERROU_PAIRING_CHECK=1, SAFIRA_CAPTURE_DIR, and Verrou installed and running"))
    func verrousPopupGoesFromNotLinkedToThePairingCode() async throws {
        let original = try #require(ExtensionHostTests.verrouFolder)
        let captures = try #require(Self.captureFolder)
        let copy = FileManager.default.temporaryDirectory.appending(path: "safira-verrou-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: original, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let profile = try ExtensionHostTests.profile()
        let host = try #require(profile.extensions)
        let loaded = try await host.loadUnpacked(at: copy)
        try await ExtensionHostTests.loadBackgroundContent(of: profile)
        let popups = ExtensionActionTests.PopupRecorder(host: host)

        host.performAction(extensionID: loaded.identifier)
        try await waitUntil("Verrou's popup was presented") { popups.presented.count == 1 }
        let webView = try #require(popups.presented.first?.action.popupWebView)
        // WebKit paints a page only in a window; this one stays off every display.
        let window = TestWindow.host(webView, width: 360, height: 300)
        defer { window.close() }
        try await waitUntilAsync("Verrou's popup shows it is not linked") {
            await ExtensionActionTests.evaluate("document.getElementById('state')?.textContent ?? ''", in: webView)
                == "Not linked"
        }
        try await Self.capture(webView, to: captures.appending(path: "popup-not-linked.png"))

        _ = await ExtensionActionTests.evaluate("(document.querySelector('#main button')?.click(), '')", in: webView)
        try await waitUntilAsync("Verrou's popup shows the pairing code", timeout: .seconds(20)) {
            let code = await ExtensionActionTests.evaluate("document.querySelector('.code')?.textContent ?? ''", in: webView)
            return code?.contains(/^\d{3} ?\d{3}$/) == true
        }
        #expect(await ExtensionActionTests.evaluate("document.getElementById('state')?.textContent ?? ''", in: webView)
            == "Pairing…")
        try await Self.capture(webView, to: captures.appending(path: "popup-pairing-code.png"))
        #expect(host.nativeMessaging.openPortCount == 1)
    }

    static func capture(_ webView: WKWebView, to file: URL) async throws {
        try await Task.sleep(for: .milliseconds(300))
        let image = try await webView.takeSnapshot(configuration: nil)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: file)
    }
}
