// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Foundation
import SafiraCore
@testable import SafiraWeb
import Testing
import WebKit

/// Extensions' action buttons and popups, on real WebKit with `.inMemory` Profiles: nothing reaches the disk or the
/// keychain, and no extension here stores a `CryptoKey`.
@MainActor
@Suite(.serialized, .oneWebKitTestAtATime) struct ExtensionActionTests {
    @Test func moreThanTwoActionsGoIntoTheOverflow() {
        #expect(ExtensionActionLayout(identifiers: []) == .buttons([]))
        #expect(ExtensionActionLayout(identifiers: ["a", "b"]) == .buttons(["a", "b"]))
        #expect(ExtensionActionLayout(identifiers: ["a", "b", "c"]) == .overflow(["a", "b", "c"]))
    }

    @Test func anExtensionWithAnActionGetsAButtonWhoseBadgeTheServiceWorkerSets() async throws {
        let folder = try Self.actionExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = try ExtensionHostTests.profile()
        let host = try #require(profile.extensions)
        try await host.loadUnpacked(at: folder)

        let item = try #require(host.actions.items.first)
        #expect(host.actions.items.count == 1)
        #expect(item.id == "pfikphmpnbnmihdgfbljkjgfnamcpjme")
        #expect(item.name == "Safira action fixture")
        #expect(item.label == "Fixture action")
        #expect(item.isEnabled)
        #expect(item.icon != nil)

        try await ExtensionHostTests.loadBackgroundContent(of: profile)
        try await waitUntil("the service worker set the badge") { host.actions.items.first?.badgeText == "3" }
        #expect(host.actions.layout == .buttons(["pfikphmpnbnmihdgfbljkjgfnamcpjme"]))
    }

    @Test func anExtensionWithNoActionGetsNoButton() async throws {
        let folder = try ExtensionHostTests.fixtureExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = try ExtensionHostTests.profile()
        let host = try #require(profile.extensions)
        try await host.loadUnpacked(at: folder)
        #expect(host.actions.items.isEmpty)
    }

    @Test func performingTheActionPresentsThePopupsWebView() async throws {
        let folder = try Self.actionExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let profile = try ExtensionHostTests.profile()
        let host = try #require(profile.extensions)
        let loaded = try await host.loadUnpacked(at: folder)
        try await ExtensionHostTests.loadBackgroundContent(of: profile)
        let popups = PopupRecorder(host: host)

        host.performAction(extensionID: loaded.identifier)
        try await waitUntil("the popup was presented") { popups.presented.count == 1 }
        #expect(popups.presented.first?.id == loaded.identifier)
        let webView = try #require(popups.presented.first?.action.popupWebView)
        try await waitUntilAsync("the popup's script ran") {
            await Self.text(of: webView) == "Fixture popup: ready"
        }
        #expect(webView.url?.absoluteString == "webkit-extension://\(loaded.identifier)/popup.html")
    }

    @Test func theButtonFollowsTheActiveTabAndIsDisabledWhereTheExtensionDisablesIt() async throws {
        let folder = try Self.actionExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = try await AnyHostServer.start()
        let profile = try ExtensionHostTests.profile()
        let host = try #require(profile.extensions)
        try await host.loadUnpacked(at: folder)
        try await ExtensionHostTests.loadBackgroundContent(of: profile)

        let plain = profile.session.openExternalLink(URL(string: "about:blank")!)
        try await waitUntil("the plain Tab is active") { host.activeTab?.id == plain }
        let disabling = profile.session.openExternalLink(server.url(host: "127.0.0.1").appending(queryItems: [
            URLQueryItem(name: "disable", value: nil),
        ]))
        try await waitUntil("the extension disabled its action in the active Tab") {
            host.activeTab?.id == disabling && host.actions.items.first?.isEnabled == false
        }
        #expect(host.actions.items.first?.badgeText == "off")

        profile.session.select(plain)
        try await waitUntil("the plain Tab's action is back") {
            host.actions.items.first?.isEnabled == true && host.actions.items.first?.badgeText == "3"
        }
        server.stop()
    }

    @Test func theServiceWorkerOpeningThePopupPresentsIt() async throws {
        let folder = try Self.actionExtension()
        defer { try? FileManager.default.removeItem(at: folder) }
        let server = try await AnyHostServer.start()
        let profile = try ExtensionHostTests.profile()
        let host = try #require(profile.extensions)
        let loaded = try await host.loadUnpacked(at: folder)
        try await ExtensionHostTests.loadBackgroundContent(of: profile)
        let popups = PopupRecorder(host: host)

        _ = profile.session.openExternalLink(server.url(host: "127.0.0.1").appending(queryItems: [
            URLQueryItem(name: "open", value: nil),
        ]))
        try await waitUntil("action.openPopup() presented the popup") { popups.presented.count == 1 }
        #expect(popups.presented.first?.id == loaded.identifier)
        #expect(popups.presented.first?.action.popupWebView != nil)
        server.stop()
    }

    /// Verrou's popup with no native bridge yet (#140): it loads, asks its service worker for the state of the link,
    /// and says it is not linked to Verrou. It needs Verrou installed, so it does not run in CI.
    @Test(.enabled(if: ExtensionHostTests.verrouFolder != nil, "needs Verrou's extension folder"))
    func verrousPopupLoadsAndShowsItIsNotLinked() async throws {
        let original = try #require(ExtensionHostTests.verrouFolder)
        let copy = FileManager.default.temporaryDirectory.appending(path: "safira-verrou-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: original, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        let profile = try ExtensionHostTests.profile()
        let host = try #require(profile.extensions)
        let loaded = try await host.loadUnpacked(at: copy)
        try await ExtensionHostTests.loadBackgroundContent(of: profile)
        let item = try #require(host.actions.items.first)
        #expect(item.name == "Verrou")
        #expect(item.label == "Verrou")
        #expect(item.icon != nil)
        let popups = PopupRecorder(host: host)

        host.performAction(extensionID: loaded.identifier)
        try await waitUntil("Verrou's popup was presented") { popups.presented.count == 1 }
        let webView = try #require(popups.presented.first?.action.popupWebView)
        try await waitUntilAsync("Verrou's popup shows its state") {
            await Self.evaluate("document.getElementById('state')?.textContent ?? ''", in: webView) == "Not linked"
        }
        #expect(await Self.evaluate("document.title", in: webView) == "Verrou")
    }

    // MARK: Helpers

    /// Records the popups WebKit asks the window to show, as the window's presenter would receive them.
    @MainActor
    final class PopupRecorder {
        private(set) var presented: [(id: String, action: WKWebExtension.Action)] = []

        init(host: ExtensionHost) {
            host.popupPresenter = { [weak self] id, action in self?.presented.append((id, action)) }
        }
    }

    static func text(of webView: WKWebView) async -> String? {
        await evaluate("document.body?.innerText ?? ''", in: webView)
    }

    static func evaluate(_ script: String, in webView: WKWebView) async -> String? {
        try? await webView.callAsyncJavaScript("return \(script)", contentWorld: .page) as? String
    }

    /// A Manifest V3 extension with an action, an icon and a popup. Its service worker sets the badge to "3" when it
    /// starts. On a served page whose query is `disable` it disables the action and sets the badge "off" in that Tab
    /// only; on one whose query is `open` it opens its popup (`action.openPopup()`).
    static func actionExtension() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "safira-action-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = [
            "manifest.json": """
                {
                  "manifest_version": 3,
                  "name": "Safira action fixture",
                  "version": "1.0",
                  "key": "c2FmaXJhLXRlc3Qta2V5",
                  "permissions": ["activeTab"],
                  "background": { "service_worker": "background.js", "type": "module" },
                  "action": { "default_title": "Fixture action", "default_popup": "popup.html",
                              "default_icon": { "16": "icon.png" } },
                  "content_scripts": [
                    { "matches": ["http://127.0.0.1/*"], "js": ["content.js"], "run_at": "document_idle" }
                  ]
                }
                """,
            "background.js": """
                chrome.action.setBadgeText({ text: "3" });
                chrome.runtime.onMessage.addListener((message, sender) => {
                  if (message === "disable") {
                    chrome.action.disable(sender.tab.id);
                    chrome.action.setBadgeText({ tabId: sender.tab.id, text: "off" });
                  }
                  if (message === "open") chrome.action.openPopup();
                });
                """,
            "content.js": "chrome.runtime.sendMessage(location.search.slice(1));",
            "popup.html": """
                <!doctype html><title>Fixture popup</title><body><p id="state"></p><script src="popup.js"></script>
                """,
            "popup.js": "document.getElementById('state').textContent = 'Fixture popup: ready';",
        ]
        for (name, text) in files {
            try Data(text.utf8).write(to: folder.appending(path: name))
        }
        try icon().write(to: folder.appending(path: "icon.png"))
        return folder
    }

    private static func icon() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                                    bitsPerPixel: 0))
        for x in 0..<16 {
            for y in 0..<16 { bitmap.setColor(.systemTeal, atX: x, y: y) }
        }
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
