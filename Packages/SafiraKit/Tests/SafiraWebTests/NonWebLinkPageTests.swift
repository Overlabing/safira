// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore
import SafiraSession
import SafiraWeb
import Testing
import WebKit

/// A real page that follows a link only another app can take must reach the Profile's decision and open nothing by
/// itself: no Tab, no navigation, no app.
@MainActor
@Suite(.serialized) struct NonWebLinkPageTests {
    private static let base = "https://127.0.0.1:9/"

    @MainActor private final class Recorder {
        var launcher = RecordingLauncher()
        var asked: [AppLinkPrompt] = []
        var refused: [AppLinkRefusal] = []
    }

    @MainActor private final class RecordingLauncher: ExternalAppLauncher {
        var opened: [URL] = []
        func app(toOpen url: URL) -> ExternalApp? {
            url.scheme == "mailto" ? ExternalApp(name: "Mail", location: URL(string: "file:///Applications/Mail.app")!) : nil
        }
        func open(_ url: URL, with app: ExternalApp) async throws { opened.append(url) }
    }

    private func answerNo(_ recorder: Recorder) -> AppLinkHandlers {
        AppLinkHandlers(launcher: recorder.launcher,
                        prompt: { prompt in
                            recorder.asked.append(prompt)
                            return PermissionAnswer(decision: .deny, remember: false)
                        },
                        refusal: { recorder.refused.append($0) })
    }

    @Test(arguments: [
        ("a script setting location", "location = 'mailto:team@example.test?subject=hi';"),
        ("a script assigning location.href", "location.href = 'mailto:team@example.test?subject=hi';"),
        ("an iframe", "const f = document.createElement('iframe'); f.src = 'mailto:team@example.test?subject=hi'; document.body.append(f);"),
        ("a clicked link", "const a = document.createElement('a'); a.href = 'mailto:team@example.test?subject=hi'; document.body.append(a); a.click();"),
        ("window.open", "window.open('mailto:team@example.test?subject=hi');"),
        ("window.open with window features", "window.open('mailto:team@example.test?subject=hi', '_blank', 'width=400,height=300');"),
    ])
    func aPageFollowingAMailtoLinkReachesTheDecisionAndOpensNothing(_ how: String, _ script: String) async throws {
        let profile = ProfileID(rawValue: UUID())
        let recorder = Recorder()
        do {
            let context = ProfileWebContext(profileID: profile)
            let session = ProfileSession(profileID: profile) { context.makePage(for: $0) }
            session.appLinks.handlers = answerNo(recorder)
            session.submitCommandBar(Self.base)
            let tab = try #require(session.selectedTabID)
            let webView = try #require(context.webView(for: tab))
            webView.loadHTMLString("<html><body>page</body></html>", baseURL: URL(string: Self.base))
            try await waitUntil("the page loads") { webView.url?.absoluteString == Self.base && !webView.isLoading }

            _ = try? await webView.evaluateJavaScript(script)
            try await waitUntil("\(how) reaches the decision") { !recorder.asked.isEmpty }
            await session.appLinks.settled()
            try await Task.sleep(for: .milliseconds(200))

            #expect(recorder.asked == [AppLinkPrompt(
                profileID: profile, scheme: try #require(URLScheme("mailto")),
                app: ExternalApp(name: "Mail", location: URL(string: "file:///Applications/Mail.app")!),
                requestedBy: "127.0.0.1")])
            #expect(recorder.launcher.opened.isEmpty)
            #expect(session.tabs.count == 1)
            #expect(session.popups.isEmpty)
            #expect(webView.url?.absoluteString == Self.base)
            session.tabs.map(\.id).forEach(session.close)
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aSchemeNoAppTakesIsRefusedAndNothingNavigates() async throws {
        let profile = ProfileID(rawValue: UUID())
        let recorder = Recorder()
        do {
            let context = ProfileWebContext(profileID: profile)
            let session = ProfileSession(profileID: profile) { context.makePage(for: $0) }
            session.appLinks.handlers = answerNo(recorder)
            session.submitCommandBar(Self.base)
            let tab = try #require(session.selectedTabID)
            let webView = try #require(context.webView(for: tab))
            webView.loadHTMLString("<html><body>page</body></html>", baseURL: URL(string: Self.base))
            try await waitUntil("the page loads") { webView.url?.absoluteString == Self.base && !webView.isLoading }

            _ = try? await webView.evaluateJavaScript("location = 'no-app-takes-this://x';")
            try await waitUntil("the link is refused") { !recorder.refused.isEmpty }

            #expect(recorder.refused.map(\.scheme.rawValue) == ["no-app-takes-this"])
            #expect(recorder.asked.isEmpty)
            #expect(webView.url?.absoluteString == Self.base)
            session.tabs.map(\.id).forEach(session.close)
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func webSchemesAreNotNonWebLinks() {
        for scheme in ["http", "https", "file", "about", "data", "blob", "javascript"] {
            #expect(WKWebView.handlesURLScheme(scheme), "\(scheme) is shown by WebKit itself")
        }
        for scheme in ["mailto", "slack", "zoommtg", "tel"] {
            #expect(!WKWebView.handlesURLScheme(scheme), "\(scheme) needs another app")
        }
    }
}
