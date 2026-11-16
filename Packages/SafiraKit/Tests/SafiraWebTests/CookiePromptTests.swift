// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore
import SafiraWeb
import TestSupport
import Testing
import WebKit

/// A real page served from loopback with a fake consent platform that autoconsent's bundled rules know ("WP Cookie
/// Notice for GDPR", found by its element ids), answered by the real script and handler.
@MainActor
@Suite struct CookiePromptTests {
    private static let page = """
        <!DOCTYPE html><title>shop</title><body>
        <div id="gdpr-cookie-consent-bar" style="position: fixed; left: 0; right: 0; bottom: 0; height: 80px">
          We use cookies.
          <button id="cookie_action_accept" onclick="document.body.dataset.consent = 'accepted'">Accept</button>
          <button id="cookie_action_reject"
                  onclick="document.body.dataset.consent = 'rejected'; this.parentElement.remove()">Reject</button>
        </div>
        </body>
        """
    private static let promptWorld = WKContentWorld.world(name: "SafiraCookiePrompts")
    private let window = TestWindow.make(width: 800, height: 600)

    @Test func aKnownPromptIsRejectedAndTheTabSaysSo() async throws {
        let server = try await LocalServer.start(.http, html: Self.page)
        defer { server.stop() }
        let (context, page) = load(server, WebContentSettings())

        try await waitUntil("the page answers") { page.state.cookiePrompt?.outcome == .rejected }

        #expect(try await consent(in: page) == "rejected")
        #expect(try await bannerIsShown(in: page) == false)
        #expect(page.state.cookiePrompt == CookiePromptReport(site: "127.0.0.1", platform: "WP Cookie Notice for GDPR",
                                                              outcome: .rejected))
        close(page, context)
    }

    @Test func theFeatureMakesNoRequestOfItsOwn() async throws {
        let server = try await LocalServer.start(.http, html: Self.page)
        defer { server.stop() }
        let (context, page) = load(server, WebContentSettings())

        try await waitUntil("the page answers") { page.state.cookiePrompt?.outcome == .rejected }
        try await Task.sleep(for: .milliseconds(500))

        #expect(server.requestCount == 1, "\(server.requestLines)")
        #expect(server.requestLines.allSatisfy { $0.hasPrefix("GET / HTTP/1.1") })
        close(page, context)
    }

    @Test func anExceptedSiteKeepsItsPrompt() async throws {
        let server = try await LocalServer.start(.http, html: Self.page)
        defer { server.stop() }
        let (context, page) = load(server, WebContentSettings(cookiePrompts: CookiePromptSettings(exceptions: ["127.0.0.1"])))

        try await waitUntil("the page loads") { !page.webView.isLoading && page.webView.url != nil }
        try await Task.sleep(for: .seconds(2))

        #expect(try await consent(in: page) == nil)
        #expect(try await bannerIsShown(in: page) == true)
        #expect(page.state.cookiePrompt == nil)
        close(page, context)
    }

    @Test func anExceptionAddedLaterReachesTheNextLoad() async throws {
        let server = try await LocalServer.start(.http, html: Self.page)
        defer { server.stop() }
        let (context, page) = load(server, WebContentSettings())
        try await waitUntil("the page answers") { page.state.cookiePrompt?.outcome == .rejected }

        context.webContentSettings.cookiePrompts.addException(forHost: "127.0.0.1")
        page.reload()
        try await waitUntil("the page reloads") { page.state.cookiePrompt == nil && !page.webView.isLoading }
        try await Task.sleep(for: .seconds(2))

        #expect(try await bannerIsShown(in: page) == true)
        #expect(page.state.cookiePrompt == nil)
        close(page, context)
    }

    @Test func withTheSwitchOffNothingIsInjected() async throws {
        let server = try await LocalServer.start(.http, html: Self.page)
        defer { server.stop() }
        let (context, page) = load(server, WebContentSettings(cookiePrompts: CookiePromptSettings(isRejecting: false)))

        try await waitUntil("the page loads") { !page.webView.isLoading && page.webView.url != nil }
        try await Task.sleep(for: .seconds(2))

        let scripts = page.webView.configuration.userContentController.userScripts
        #expect(!scripts.contains { $0.source.contains("autoconsentSendMessage") })
        #expect(try await page.webView.evaluateJavaScript("typeof window.autoconsentReceiveMessage", in: nil,
                                                          contentWorld: Self.promptWorld) as? String == "undefined")
        #expect(try await consent(in: page) == nil)
        #expect(try await bannerIsShown(in: page) == true)
        close(page, context)
    }

    @Test func thePageCannotReachTheScript() async throws {
        let server = try await LocalServer.start(.http, html: Self.page)
        defer { server.stop() }
        let (context, page) = load(server, WebContentSettings())
        try await waitUntil("the page answers") { page.state.cookiePrompt?.outcome == .rejected }

        #expect(try await page.webView.evaluateJavaScript("typeof window.autoconsentReceiveMessage", in: nil,
                                                          contentWorld: Self.promptWorld) as? String == "function")
        #expect(try await page.webView.evaluateJavaScript("typeof window.autoconsentReceiveMessage") as? String
            == "undefined")
        #expect(try await page.webView.evaluateJavaScript("typeof window.webkit?.messageHandlers?.safiraCookiePrompts")
            as? String == "undefined")
        close(page, context)
    }

    @Test func aNewDocumentStartsWithoutAReport() async throws {
        let server = try await LocalServer.start(.http, html: Self.page)
        let plain = try await LocalServer.start(.http, title: "plain")
        defer { server.stop(); plain.stop() }
        let (context, page) = load(server, WebContentSettings())
        try await waitUntil("the page answers") { page.state.cookiePrompt?.outcome == .rejected }

        page.load(try #require(URL(string: "http://127.0.0.1:\(plain.port)/")), httpsFirst: false)
        try await waitUntil("the other page loads") { page.webView.title == "plain" && !page.webView.isLoading }

        #expect(page.state.cookiePrompt == nil)
        close(page, context)
    }

    private func load(_ server: LocalServer, _ settings: WebContentSettings) -> (ProfileWebContext, WebKitPage) {
        let context = ProfileWebContext(profileID: ProfileID(rawValue: UUID()), webContentSettings: settings,
                                        storage: .inMemory)
        let page = context.makePage(for: TabID())
        // autoconsent checks that the prompt is visible, which needs a laid-out page.
        window.contentView = page.webView
        page.load(URL(string: "http://127.0.0.1:\(server.port)/")!, httpsFirst: false)
        return (context, page)
    }

    private func consent(in page: WebKitPage) async throws -> String? {
        try await page.webView.evaluateJavaScript("document.body.dataset.consent ?? null") as? String
    }

    private func bannerIsShown(in page: WebKitPage) async throws -> Bool {
        let script = """
            (() => { const bar = document.getElementById('gdpr-cookie-consent-bar');
                     return bar !== null && getComputedStyle(bar).display !== 'none'
                         && getComputedStyle(bar).opacity !== '0'; })()
            """
        return try await page.webView.evaluateJavaScript(script) as? Bool ?? false
    }

    private func close(_ page: WebKitPage, _ context: ProfileWebContext) {
        page.close()
        window.close()
        _ = context
    }
}
