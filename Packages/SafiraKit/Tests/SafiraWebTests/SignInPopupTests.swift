// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraWeb
import Testing
import WebKit

/// A popup sign-in through real WebKit against a loopback site and identity provider (`SignInSite`): the popup shares
/// the opener's Profile data store and `window.opener`, ends when it closes itself, and another Profile sees none of it.
@MainActor
@Suite(.serialized) struct SignInPopupTests {
    private func makeSession(_ profile: ProfileID) -> (ProfileSession, ProfileWebContext) {
        let context = ProfileWebContext(profileID: profile)
        let session = ProfileSession(profileID: profile) { context.makePage(for: $0) }
        return (session, context)
    }

    private func open(_ url: URL, in session: ProfileSession, _ context: ProfileWebContext) async throws -> WKWebView {
        session.openCommandBar(for: .newTab)
        session.submitCommandBar(url.absoluteString)
        let webView = try #require(session.selectedTabID.flatMap(context.webView(for:)))
        try await waitUntil("\(url.path()) loads") { webView.url == url && !webView.isLoading && webView.title != "" }
        return webView
    }

    private func click(_ id: String, in webView: WKWebView) async throws {
        _ = try await webView.evaluateJavaScript("document.getElementById('\(id)').click()")
    }

    private func closeAll(_ session: ProfileSession) {
        session.popups.map(\.id).forEach(session.closePopup)
        for space in session.spaces {
            space.tabs.map(\.id).forEach(session.close)
        }
    }

    @Test func aRepresentativePopupSignInCompletesAndLeavesTheOpenerSignedInWhileAnotherProfileIsNot() async throws {
        let site = try await SignInSite()
        let work = ProfileID(rawValue: UUID())
        let personal = ProfileID(rawValue: UUID())
        do {
            let (session, context) = makeSession(work)
            let (other, otherContext) = makeSession(personal)
            let opener = try await open(site.app("/app"), in: session, context)
            #expect(opener.title == "app: signed out")

            try await click("signin", in: opener)
            try await waitUntil("the popup opens") { !session.popups.isEmpty }

            let popup = try #require(session.popups.first)
            #expect(session.tabs.count == 1)
            #expect(popup.requestedWindow == RequestedWindow(width: 480, height: 640))
            #expect(context.webView(forPopup: popup.id) != nil)

            try await waitUntil("the popup closes itself") { session.popups.isEmpty }
            try await waitUntil("the opener is signed in") { opener.title == "app: signed in as alice" }
            #expect(session.tabs.count == 1)
            #expect(await context.dataStore.httpCookieStore.allCookies().map(\.name).sorted()
                == ["app_session", "idp_session"])

            let again = try await open(site.app("/whoami"), in: session, context)
            #expect(again.title == "app: app_session=alice")
            let stranger = try await open(site.app("/whoami"), in: other, otherContext)
            #expect(stranger.title == "app: anonymous")
            #expect(await otherContext.dataStore.httpCookieStore.allCookies() == [])

            closeAll(session)
            closeAll(other)
        }
        await removeDataStoreWhenReleased(work)
        await removeDataStoreWhenReleased(personal)
    }

    @Test func aScriptedWindowOpenWithoutFeaturesAndATargetBlankLinkStillOpenBackgroundTabs() async throws {
        let site = try await SignInSite()
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context) = makeSession(profile)
            let opener = try await open(site.app("/app"), in: session, context)
            let openerTab = try #require(session.selectedTabID)

            try await click("plain", in: opener)
            try await waitUntil("a background Tab opens") { session.tabs.count == 2 }
            try await click("blank", in: opener)
            try await waitUntil("a second background Tab opens") { session.tabs.count == 3 }

            #expect(session.popups.isEmpty)
            #expect(session.selectedTabID == openerTab)
            #expect(session.tabs.first?.id == openerTab)
            closeAll(session)
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func closingTheOpenerClosesTheWebViewOfItsPopup() async throws {
        let site = try await SignInSite()
        let profile = ProfileID(rawValue: UUID())
        do {
            let (session, context) = makeSession(profile)
            let opener = try await open(site.app("/app"), in: session, context)
            try await click("hold", in: opener)
            try await waitUntil("the popup opens") { !session.popups.isEmpty }
            let popupID = try #require(session.popups.first?.id)
            #expect(context.webView(forPopup: popupID) != nil)

            session.closeSelectedTab()

            #expect(session.popups.isEmpty)
            #expect(context.webView(forPopup: popupID) == nil)
        }
        await removeDataStoreWhenReleased(profile)
    }
}
