// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore
import SafiraSession
import SafiraWeb
import Testing
import WebKit

/// Every way a real page can reach a link only another app can take (a redirect, a refresh, a form, a link with a
/// target, a popup, a ⌘-click) must end at the Profile's question and open nothing by itself. The scheme is one no app
/// on this Mac takes, so a route that slipped past the question would fail quietly instead of opening an app.
@MainActor
@Suite(.serialized) struct NonWebLinkRouteTests {
    private static let scheme = "safira-verify"
    private static let link = "safira-verify://open?x=1"

    @MainActor private final class Harness {
        let profile: ProfileID
        let context: ProfileWebContext
        let session: ProfileSession
        var opened: [URL] = []
        var asked: [AppLinkPrompt] = []

        init(profile: ProfileID, scheme: String) {
            self.profile = profile
            context = ProfileWebContext(profileID: profile)
            session = ProfileSession(profileID: profile) { [context] in context.makePage(for: $0) }
            session.appLinks.handlers = AppLinkHandlers(
                launcher: Launcher(scheme: scheme, harness: self),
                prompt: { [unowned self] prompt in
                    asked.append(prompt)
                    return PermissionAnswer(decision: .deny, remember: false)
                })
        }

        func open(_ url: URL) async throws -> WKWebView {
            session.openCommandBar(for: .newTab)
            session.submitCommandBar(url.absoluteString)
            let webView = try #require(session.selectedTabID.flatMap(context.webView(for:)))
            try await waitUntil("\(url.path()) loads") { webView.url == url && !webView.isLoading }
            return webView
        }

        /// Waits for the first question, then long enough for a second one or a stray navigation to show up.
        func settle() async throws {
            try await waitUntil("the page reaches the question") { !asked.isEmpty }
            await session.appLinks.settled()
            try await Task.sleep(for: .milliseconds(300))
        }

        func closeAll() {
            session.popups.map(\.id).forEach(session.closePopup)
            session.tabs.map(\.id).forEach(session.close)
        }
    }

    @MainActor private final class Launcher: ExternalAppLauncher {
        let scheme: String
        unowned let harness: Harness
        init(scheme: String, harness: Harness) {
            self.scheme = scheme
            self.harness = harness
        }
        func app(toOpen url: URL) -> ExternalApp? {
            url.scheme == scheme ? ExternalApp(name: "Example", location: URL(string: "file:///Applications/Example.app")!) : nil
        }
        func open(_ url: URL, with app: ExternalApp) async throws { harness.opened.append(url) }
    }

    private func prompt(_ harness: Harness, scheme: String = NonWebLinkRouteTests.scheme) throws -> AppLinkPrompt {
        AppLinkPrompt(profileID: harness.profile, scheme: try #require(URLScheme(scheme)),
                      app: ExternalApp(name: "Example", location: URL(string: "file:///Applications/Example.app")!),
                      requestedBy: "127.0.0.1")
    }

    private func run(scheme: String = NonWebLinkRouteTests.scheme, _ pages: [String: RoutedPageServer.Page],
                     _ body: (Harness, RoutedPageServer) async throws -> Void) async throws {
        let server = try await RoutedPageServer.start(pages)
        defer { server.stop() }
        let profile = ProfileID(rawValue: UUID())
        var failure: (any Error)?
        do {
            let harness = Harness(profile: profile, scheme: scheme)
            do {
                try await body(harness, server)
            } catch {
                failure = error
            }
            harness.closeAll()
        }
        await removeDataStoreWhenReleased(profile)
        if let failure { throw failure }
    }

    @Test func aRedirectOfTheMainFrameToTheSchemeAsksAndLeavesThePageWhereItWas() async throws {
        try await run(["/home": .html("home"), "/redirect": .redirect(to: Self.link)]) { harness, server in
            let webView = try await harness.open(server.url("/home"))

            _ = try await webView.evaluateJavaScript("location = '/redirect'")
            try await harness.settle()

            let expected = try prompt(harness)
            #expect(harness.asked.map(\.scheme) == [expected.scheme])
            #expect(harness.asked.map(\.app) == [expected.app])
            // While the redirect is pending WebKit already reports the link as the page's address, so the question
            // names the link's host ("open") instead of the page that asked.
            withKnownIssue("the Tab's address during a pending redirect is the redirect target") {
                #expect(harness.asked.map(\.requestedBy) == ["127.0.0.1"])
            }
            #expect(harness.opened.isEmpty)
            #expect(webView.url == server.url("/home"))
            #expect(harness.session.tabs.count == 1)
        }
    }

    @Test func aRedirectInsideAnIframeAsksAndLeavesThePageWhereItWas() async throws {
        try await run(["/page": .html("<iframe src='/redirect'></iframe>"), "/redirect": .redirect(to: Self.link)]) {
            harness, server in
            let webView = try await harness.open(server.url("/page"))
            try await harness.settle()

            #expect(harness.asked == [try prompt(harness)])
            #expect(harness.opened.isEmpty)
            #expect(webView.url == server.url("/page"))
            #expect(harness.session.tabs.count == 1)
        }
    }

    @Test func aMetaRefreshToTheSchemeAsksAndTheRefreshingPageStays() async throws {
        let refresh = "<meta http-equiv='refresh' content='0;url=\(Self.link)'>"
        try await run(["/refresh": RoutedPageServer.Page(body: "<!DOCTYPE html><html><head>\(refresh)</head><body>wait</body></html>")]) {
            harness, server in
            harness.session.openCommandBar(for: .newTab)
            harness.session.submitCommandBar(server.url("/refresh").absoluteString)
            try await harness.settle()

            let webView = try #require(harness.session.selectedTabID.flatMap(harness.context.webView(for:)))
            #expect(harness.asked == [try prompt(harness)])
            #expect(harness.opened.isEmpty)
            #expect(webView.url == server.url("/refresh"))
            #expect(harness.session.tabs.count == 1)
        }
    }

    @Test(arguments: ["post", "get"])
    func aFormSubmittedToTheSchemeAsksAndLeavesThePageWhereItWas(method: String) async throws {
        let form = "<form id='f' action='\(Self.link)' method='\(method)'><input name='a' value='b'></form>"
        try await run(["/form": .html(form)]) { harness, server in
            let webView = try await harness.open(server.url("/form"))

            _ = try await webView.evaluateJavaScript("document.getElementById('f').submit()")
            try await harness.settle()

            #expect(harness.asked == [try prompt(harness)])
            #expect(harness.opened.isEmpty)
            #expect(webView.url == server.url("/form"))
            #expect(harness.session.tabs.count == 1)
        }
    }

    @Test func aLinkWithTargetBlankToTheSchemeAsksAndOpensNoTab() async throws {
        try await run(["/page": .html("<a id='l' href='\(Self.link)' target='_blank'>open</a>")]) { harness, server in
            let webView = try await harness.open(server.url("/page"))

            _ = try await webView.evaluateJavaScript("document.getElementById('l').click()")
            try await harness.settle()

            #expect(harness.asked == [try prompt(harness)])
            #expect(harness.opened.isEmpty)
            #expect(harness.session.tabs.count == 1)
            #expect(harness.session.popups.isEmpty)
            #expect(webView.url == server.url("/page"))
        }
    }

    @Test func aLinkInsideAnIframeWithTargetTopAsksAndTheTopPageStays() async throws {
        try await run(["/page": .html("<iframe id='frame' src='/inner'></iframe>"),
                       "/inner": .html("<a id='l' href='\(Self.link)' target='_top'>open</a>")]) { harness, server in
            let webView = try await harness.open(server.url("/page"))
            try await waitUntilAsync("the iframe has its link") {
                (try? await webView.evaluateJavaScript(
                    "document.getElementById('frame').contentDocument.getElementById('l') !== null") as? Bool) == true
            }

            _ = try await webView.evaluateJavaScript("document.getElementById('frame').contentDocument.getElementById('l').click()")
            try await harness.settle()

            #expect(harness.asked == [try prompt(harness)])
            #expect(harness.opened.isEmpty)
            #expect(webView.url == server.url("/page"))
            #expect(harness.session.tabs.count == 1)
        }
    }

    @Test func aLinkInsideASignInPopupPanelAsksFromThePopupAndLeavesItOpen() async throws {
        try await run(["/app": .html("<button id='open' onclick=\"window.open('/popup', 'signin', 'width=480,height=640')\">Sign in</button>"),
                       "/popup": .html("<a id='l' href='\(Self.link)'>open</a>")]) { harness, server in
            let opener = try await harness.open(server.url("/app"))
            _ = try await opener.evaluateJavaScript("document.getElementById('open').click()")
            try await waitUntil("the popup opens") { !harness.session.popups.isEmpty }
            let popupID = try #require(harness.session.popups.first?.id)
            let popup = try #require(harness.context.webView(forPopup: popupID))
            try await waitUntil("the popup loads") { popup.url == server.url("/popup") && !popup.isLoading }

            _ = try await popup.evaluateJavaScript("document.getElementById('l').click()")
            try await harness.settle()

            #expect(harness.asked == [try prompt(harness)])
            #expect(harness.opened.isEmpty)
            #expect(harness.session.popups.map(\.id) == [popupID])
            #expect(popup.url == server.url("/popup"))
            #expect(harness.session.tabs.count == 1)
            #expect(opener.url == server.url("/app"))
        }
    }

    @Test func aCommandClickOnAMailtoLinkAsksAndOpensNoEmptyTabWhileOneOnAWebLinkStillDoes() async throws {
        let links = "<a id='mail' href='mailto:team@example.test?subject=hi'>mail</a><a id='web' href='/docs'>docs</a>"
        try await run(scheme: "mailto", ["/page": .html(links), "/docs": .html("docs")]) { harness, server in
            let webView = try await harness.open(server.url("/page"))
            // A script cannot stand for a ⌘-click: WebKit takes the modifiers of a real event only. The window is
            // never shown.
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = webView
            defer { window.contentView = nil; window.close() }
            @MainActor func commandClick(_ id: String) async throws {
                let box = try #require(try await webView.evaluateJavaScript("""
                    (() => { const r = document.getElementById('\(id)').getBoundingClientRect();
                             return [r.left + r.width / 2, r.top + r.height / 2]; })()
                    """) as? [Double])
                let point = webView.convert(NSPoint(x: box[0], y: box[1]), to: nil)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = try #require(NSEvent.mouseEvent(
                        with: type, location: point, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                    type == .leftMouseDown ? webView.mouseDown(with: event) : webView.mouseUp(with: event)
                }
            }

            try await commandClick("web")
            try await waitUntil("the web link opens a background Tab") { harness.session.tabs.count == 2 }

            try await commandClick("mail")
            try await harness.settle()

            #expect(harness.asked == [try prompt(harness, scheme: "mailto")])
            #expect(harness.opened.isEmpty)
            #expect(harness.session.tabs.count == 2)
            #expect(webView.url == server.url("/page"))
        }
    }
}
