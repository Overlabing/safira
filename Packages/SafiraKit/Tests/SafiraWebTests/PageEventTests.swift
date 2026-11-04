// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore
import SafiraSession
import SafiraWeb
import Testing
import WebKit

/// What a real page reports through the real session: links opened in new Tabs, which must stay in the Profile's data
/// store, and media playback.
@MainActor
@Suite struct PageEventTests {
    /// Port 9 refuses connections at once, so the page never reaches the network.
    private static let base = "https://127.0.0.1:9/"

    @Test func aTargetBlankLinkOpensABackgroundTabInTheProfileDataStore() async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context, opener) = try await openPage(
                profile, body: #"<a id="link" target="_blank" href="\#(Self.base)blank">blank</a>"#)

            _ = try await context.webView(for: opener)?.evaluateJavaScript("document.getElementById('link').click()")
            try await waitUntil("the link opens a Tab") { session.tabs.count == 2 }

            let newTab = try #require(session.tabs.last)
            let webView = try #require(context.webView(for: newTab.id))
            #expect(webView.configuration.websiteDataStore === context.dataStore)
            #expect(webView.configuration.websiteDataStore.identifier == profile.rawValue)
            #expect(session.selectedTabID == opener)
            #expect(context.webView(for: opener)?.url?.absoluteString == Self.base)
            close(session)
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aCommandClickedLinkOpensABackgroundTabInTheProfileDataStore() async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context, opener) = try await openPage(
                profile, body: #"<a id="link" href="\#(Self.base)other">other</a>"#)

            try commandClick(context.webView(for: opener))
            try await waitUntil("the link opens a Tab") { session.tabs.count == 2 }

            let newTab = try #require(session.tabs.last)
            let webView = try #require(context.webView(for: newTab.id))
            #expect(webView.configuration.websiteDataStore === context.dataStore)
            #expect(webView.configuration.websiteDataStore.identifier == profile.rawValue)
            #expect(newTab.address?.absoluteString == "\(Self.base)other")
            #expect(session.selectedTabID == opener)
            try await Task.sleep(for: .milliseconds(200))
            #expect(context.webView(for: opener)?.url?.absoluteString == Self.base)
            #expect(session.tabs.count == 2)
            close(session)
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aCommandClickedTargetBlankLinkOpensOneTab() async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context, opener) = try await openPage(
                profile, body: #"<a id="link" target="_blank" href="\#(Self.base)blank">blank</a>"#)

            try commandClick(context.webView(for: opener))
            try await waitUntil("the link opens a Tab") { session.tabs.count >= 2 }
            try await Task.sleep(for: .milliseconds(300))

            #expect(session.tabs.count == 2)
            #expect(session.selectedTabID == opener)
            close(session)
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aTabShowsWhenItsPagePlaysMedia() async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context, opener) = try await openPage(
                profile, body: #"<audio id="audio" loop src="data:audio/wav;base64,\#(Self.silentWAV)"></audio>"#)
            let webView = try #require(context.webView(for: opener))

            _ = try await webView.callAsyncJavaScript("await document.getElementById('audio').play()",
                                                      contentWorld: .page)
            try await waitUntil("the Tab shows media playing") { session.selectedTab?.state.isPlayingMedia == true }

            _ = try await webView.evaluateJavaScript("document.getElementById('audio').pause()")
            try await waitUntil("the Tab shows media stopped") { session.selectedTab?.state.isPlayingMedia == false }
            close(session)
        }
        await removeDataStoreWhenReleased(profile)
    }

    /// One second of silence: 8 kHz, mono, 8-bit PCM.
    private static let silentWAV: String = {
        let samples = 8000
        func bytes(_ value: UInt32, _ count: Int) -> [UInt8] { (0..<count).map { UInt8(value >> (8 * $0) & 0xFF) } }
        var wav = Array("RIFF".utf8) + bytes(UInt32(36 + samples), 4) + Array("WAVEfmt ".utf8)
        wav += bytes(16, 4) + bytes(1, 2) + bytes(1, 2) + bytes(8000, 4) + bytes(8000, 4) + bytes(1, 2) + bytes(8, 2)
        wav += Array("data".utf8) + bytes(UInt32(samples), 4) + Array(repeating: 128, count: samples)
        return Data(wav).base64EncodedString()
    }()

    private let window: NSWindow = {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }()

    private func close(_ session: ProfileSession) {
        session.tabs.map(\.id).forEach(session.close)
        window.close()
    }

    /// Sends the mouse events of a click with ⌘ held to the middle of the web view, as the user would.
    private func commandClick(_ webView: WKWebView?) throws {
        let webView = try #require(webView)
        let point = webView.convert(NSPoint(x: webView.bounds.midX, y: webView.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
    }

    /// A session of one Tab showing a page with the given body, its pages built by the Profile's web context.
    private func openPage(_ profile: ProfileID, body: String) async throws
        -> (ProfileSession, ProfileWebContext, TabID) {
        let context = ProfileWebContext(profileID: profile)
        let session = ProfileSession(profile: Profile(id: profile, name: "Test")) { context.makePage(for: $0) }
        session.submitCommandBar(Self.base)
        let opener = try #require(session.selectedTabID)
        let webView = try #require(context.webView(for: opener))
        // A real ⌘-click needs the page in a window; the link fills the page so the click lands on it.
        window.contentView = webView
        window.orderFrontRegardless()
        let style = "<style>a { display: block; position: fixed; inset: 0; }</style>"
        webView.loadHTMLString("<html><head>\(style)</head><body>\(body)</body></html>", baseURL: URL(string: Self.base))
        try await waitUntil("the page loads") {
            webView.url?.absoluteString == Self.base && !webView.isLoading
        }
        return (session, context, opener)
    }
}
