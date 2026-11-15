// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraWeb
import Testing
import WebKit

/// Every page Safira builds (a Profile's Tab, a Private window's Tab, a popup) allows a page's full screen request and
/// sends Safari's `Version/… Safari/605.1.15` tokens.
@MainActor
@Suite(.serialized) struct PageConfigurationTests {
    private func userAgent(of webView: WKWebView) async throws -> String {
        try #require(try await webView.evaluateJavaScript("navigator.userAgent") as? String)
    }

    private func expectSafariUserAgent(_ userAgent: String) {
        #expect(userAgent.hasSuffix(" (KHTML, like Gecko) \(SafariUserAgent.current)"))
        #expect(userAgent.hasSuffix(" Safari/605.1.15"))
        #expect(userAgent.contains(" Version/"))
        #expect(!userAgent.contains("Safira"))
    }

    @Test func aTabOfAProfileAllowsFullScreenAndSendsSafarisTokens() async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let page = ProfileWebContext(profileID: profile).makePage(for: TabID())
            #expect(page.webView.configuration.preferences.isElementFullscreenEnabled == true)
            #expect(page.webView.configuration.applicationNameForUserAgent == SafariUserAgent.current)
            expectSafariUserAgent(try await userAgent(of: page.webView))
            page.close()
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aTabOfAPrivateWindowAllowsFullScreenAndSendsSafarisTokens() async throws {
        let context = ProfileWebContext(privateWindowOf: ProfileID(rawValue: UUID()))
        let page = context.makePage(for: TabID())
        #expect(context.isPrivate)
        #expect(page.webView.configuration.preferences.isElementFullscreenEnabled == true)
        expectSafariUserAgent(try await userAgent(of: page.webView))
        page.close()
    }

    @Test func aPopupAndALinkOpenedInANewTabKeepBoth() async throws {
        let site = try await SignInSite()
        let profile = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let session = ProfileSession(profileID: profile) { context.makePage(for: $0) }
            session.openCommandBar(for: .newTab)
            session.submitCommandBar(site.app("/app").absoluteString)
            let opener = try #require(session.selectedTabID.flatMap(context.webView(for:)))
            try await waitUntil("the opener loads") { !opener.isLoading && opener.title != "" }

            _ = try await opener.evaluateJavaScript("document.getElementById('hold').click()")
            try await waitUntil("the popup opens") { !session.popups.isEmpty }
            let popup = try #require(session.popups.first.flatMap { context.webView(forPopup: $0.id) })
            #expect(popup.configuration.preferences.isElementFullscreenEnabled == true)
            expectSafariUserAgent(try await userAgent(of: popup))

            _ = try await opener.evaluateJavaScript("document.getElementById('blank').click()")
            try await waitUntil("a background Tab opens") { session.tabs.count == 2 }
            let linked = try #require(session.tabs.last.flatMap { context.webView(for: $0.id) })
            #expect(linked.configuration.preferences.isElementFullscreenEnabled == true)
            expectSafariUserAgent(try await userAgent(of: linked))

            session.popups.map(\.id).forEach(session.closePopup)
            for space in session.spaces { space.tabs.map(\.id).forEach(session.close) }
        }
        await removeDataStoreWhenReleased(profile)
    }
}
