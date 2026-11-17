// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraWeb
import Testing
import WebKit

/// #121: a real page's `alert()`, `confirm()`, `prompt()` and file input reach the window's panels and get the user's
/// answer, and the end of its content process reaches the Tab.
@MainActor
@Suite(.serialized, .oneWebKitTestAtATime) struct PageDialogTests {
    /// Port 9 refuses connections at once, so the page never reaches the network.
    private static let base = "https://127.0.0.1:9/"

    @MainActor private final class Panels {
        var dialogs: [PageDialog] = []
        var choices: [FileChoice] = []
        var answer = PageDialogResponse(isAccepted: true)
        var files: [URL]?

        var panels: PagePanels {
            PagePanels(dialog: { dialog in
                self.dialogs.append(dialog)
                return self.answer
            }, chooseFiles: { choice in
                self.choices.append(choice)
                return self.files
            })
        }
    }

    @Test func alertShowsTheMessageAndNamesTheSite() async throws {
        try await withPage { webView, panels in
            _ = try await webView.callAsyncJavaScript("alert('Saved'); return 1;", contentWorld: .page)

            #expect(panels.dialogs == [PageDialog(kind: .alert, message: "Saved", site: "127.0.0.1")])
        }
    }

    @Test(arguments: [true, false])
    func confirmReturnsTheUsersChoice(_ accepted: Bool) async throws {
        try await withPage { webView, panels in
            panels.answer = PageDialogResponse(isAccepted: accepted)

            let result = try await webView.callAsyncJavaScript("return confirm('Delete this?');", contentWorld: .page)

            #expect(result as? Bool == accepted)
            #expect(panels.dialogs.map(\.kind) == [.confirm])
            #expect(panels.dialogs.map(\.message) == ["Delete this?"])
        }
    }

    @Test func promptReturnsTheTypedTextAndNullOnCancel() async throws {
        try await withPage { webView, panels in
            panels.answer = PageDialogResponse(isAccepted: true, text: "Ada")
            let typed = try await webView.callAsyncJavaScript("return prompt('Your name?', 'Guest');", contentWorld: .page)
            panels.answer = PageDialogResponse(isAccepted: false, text: "ignored")
            let cancelled = try await webView.callAsyncJavaScript("return prompt('Your name?') === null;",
                                                                  contentWorld: .page)

            #expect(typed as? String == "Ada")
            #expect(cancelled as? Bool == true)
            #expect(panels.dialogs.first?.kind == .prompt(defaultText: "Guest"))
            #expect(panels.dialogs.last?.kind == .prompt(defaultText: ""))
        }
    }

    @Test func aLoopingPageIsOfferedAWayOutAndStoppedDialogsAreDeclined() async throws {
        try await withPage { webView, panels in
            panels.answer = PageDialogResponse(isAccepted: true, stopsDialogs: true)

            let result = try await webView.callAsyncJavaScript("""
                const answers = [];
                for (let i = 0; i < 5; i++) { answers.push(confirm('Again ' + i)); }
                return answers;
                """, contentWorld: .page)

            #expect(panels.dialogs.map(\.offersToStopDialogs) == [false, true])
            #expect(result as? [Bool] == [true, true, false, false, false])
        }
    }

    @Test func aFileInputGetsTheChosenFilesAndItsChoice() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "safira-upload-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        try await withPage(body: #"<input id="file" type="file" multiple>"#) { webView, panels in
            panels.files = [file]

            _ = try await webView.callAsyncJavaScript("document.getElementById('file').click(); return 1;",
                                                      contentWorld: .page)
            try await waitUntil("the open panel is asked for") { !panels.choices.isEmpty }
            var name: Any?
            for _ in 0..<100 where (name as? String) != file.lastPathComponent {
                name = try await webView.callAsyncJavaScript(
                    "const f = document.getElementById('file').files; return f.length ? f[0].name : null;",
                    contentWorld: .page)
                try await Task.sleep(for: .milliseconds(20))
            }

            #expect(panels.choices == [FileChoice(allowsMultipleSelection: true, allowsDirectories: false)])
            #expect(name as? String == file.lastPathComponent)
        }
    }

    @Test func theEndOfTheContentProcessReachesTheTab() async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let session = ProfileSession(profileID: profile) { context.makePage(for: $0) }
            session.submitCommandBar(Self.base)
            let tab = try #require(session.selectedTab)
            let webView = try #require(context.webView(for: tab.id))

            // WebKit calls the delegate by its Objective-C selector; going through the protocol proves the name matches.
            webView.navigationDelegate?.webViewWebContentProcessDidTerminate?(webView)

            #expect(tab.crash == .reloadWhenShown)
            session.tabs.map(\.id).forEach(session.close)
        }
        await removeDataStoreWhenReleased(profile)
    }

    /// A page of the Profile's web context showing `body`, whose window's panels are recorded.
    private func withPage(body: String = "page", _ test: (WKWebView, Panels) async throws -> Void) async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let panels = Panels()
            context.pagePanels = panels.panels
            let session = ProfileSession(profileID: profile) { context.makePage(for: $0) }
            session.submitCommandBar(Self.base)
            let tab = try #require(session.selectedTabID)
            let webView = try #require(context.webView(for: tab))
            webView.loadHTMLString("<html><body>\(body)</body></html>", baseURL: URL(string: Self.base))
            try await waitUntil("the page loads") { webView.url?.absoluteString == Self.base && !webView.isLoading }
            try await test(webView, panels)
            session.tabs.map(\.id).forEach(session.close)
        }
        await removeDataStoreWhenReleased(profile)
    }
}
