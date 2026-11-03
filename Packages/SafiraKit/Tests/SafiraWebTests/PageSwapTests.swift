// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore
import SafiraWeb
import Testing
import WebKit

/// Counts the navigations a web view finishes, and resumes a waiter when the next one finishes.
@MainActor
private final class NavigationCounter: NSObject, WKNavigationDelegate {
    private(set) var finished = 0
    private var waiter: CheckedContinuation<Void, Never>?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished += 1
        waiter?.resume()
        waiter = nil
    }

    func nextFinish() async {
        await withCheckedContinuation { waiter = $0 }
    }
}

@MainActor
@Suite struct PageSwapTests {
    /// The one real-WebKit check of the walking skeleton: the facade tests prove the session never asks a page to
    /// reload on selection; this proves WebKit itself does not reload a view taken out of the window and put back.
    @Test func swappingTwentyRealWebViewsInAWindowReloadsNone() async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let host = try #require(window.contentView)

            var pages: [(page: WebKitPage, counter: NavigationCounter)] = []
            for number in 1...20 {
                let page = context.makePage(for: TabID())
                let counter = NavigationCounter()
                page.webView.navigationDelegate = counter
                try page.load(#require(URL(string: "data:text/html,<title>\(number)</title>")), httpsFirst: false)
                await counter.nextFinish()
                _ = try await page.webView.evaluateJavaScript("window.marker = \(number)")
                pages.append((page, counter))
            }

            for _ in 1...3 {
                for entry in pages.shuffled() {
                    host.subviews.forEach { $0.removeFromSuperview() }
                    entry.page.webView.frame = host.bounds
                    host.addSubview(entry.page.webView)
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
            try await Task.sleep(for: .milliseconds(300))

            for (number, entry) in pages.enumerated() {
                #expect(entry.counter.finished == 1)
                // A reload would have dropped the page's script state.
                let marker = try await entry.page.webView.evaluateJavaScript("window.marker") as? Int
                #expect(marker == number + 1)
            }
            pages.forEach { $0.page.close() }
        }
        try await removeDataStoreWhenReleased(profile)
    }

    @Test func aTabPageUsesItsProfileDataStoreAndLeavesTheRegistryWhenClosed() async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let tab = TabID()

            let page = context.makePage(for: tab)

            #expect(page.webView.configuration.websiteDataStore === context.dataStore)
            #expect(context.webView(for: tab) === page.webView)

            page.close()

            #expect(context.webView(for: tab) == nil)
        }
        try await removeDataStoreWhenReleased(profile)
    }
}
