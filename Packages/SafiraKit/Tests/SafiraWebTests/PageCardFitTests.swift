// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import AppKit
import Foundation
import SafiraCore
import SafiraSession
import SafiraWeb
import SwiftUI
import Testing
import WebKit

/// The page fills the card exactly in every layout of the window: the web view's frame is the card's inner bounds, and
/// the page lays out at the card's width, so nothing of it hides past the card's edge. One window at a time: the other
/// real-WebKit suites run alongside and time their page loads.
@MainActor
@Suite(.serialized) struct PageCardFitTests {
    enum Layout: String, CaseIterable, CustomTestStringConvertible {
        case sidebarShown, compactHidden, compactRevealed, sidebarShownAfterCompact

        var presentations: [SidebarPresentation] {
            var compact = SidebarPresentation(isCompact: true)
            let hidden = compact
            compact.reveal()
            switch self {
            case .sidebarShown: return [SidebarPresentation()]
            case .compactHidden: return [hidden]
            case .compactRevealed: return [hidden, compact]
            case .sidebarShownAfterCompact: return [hidden, SidebarPresentation()]
            }
        }

        var testDescription: String { rawValue }
    }

    @Test(arguments: Layout.allCases)
    func thePageFillsTheCard(_ layout: Layout) async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let window = Window(profile: profile)
            defer { window.close() }
            let page = try await window.load()

            for presentation in layout.presentations {
                window.layout.apply(presentation, animated: false)
                window.layOut()
            }

            try await window.expectPageFillsCard(page)
            for width in [1500.0, 900, 640] {
                window.resize(width: width)
                try await window.expectPageFillsCard(page)
            }
        }
        await removeDataStoreWhenReleased(profile)
    }

    /// A Main window's layout with a real page in its card, in a window of the Main window's style that is never shown.
    @MainActor
    final class Window {
        let host = TabHostView(emptyPage: NSView())
        let canvas: PageCanvasView
        let layout: BrowserWindowLayout
        let window: NSWindow
        let context: ProfileWebContext
        private let toolbar: SidebarToolbar

        init(profile: ProfileID) {
            context = ProfileWebContext(profileID: profile)
            canvas = PageCanvasView(page: host, banner: Self.banner(), commandBar: Self.commandBar())
            layout = BrowserWindowLayout(background: NSView(), column: List { Text(verbatim: "Tab") }, canvas: canvas)
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.contentViewController = layout
            toolbar = SidebarToolbar(items: layout.toolbarItems)
            toolbar.install(in: window)
            window.setContentSize(NSSize(width: 1200, height: 800))
            layOut()
        }

        /// Like the Matching tab banner: hidden, sized by its SwiftUI content, one line of text wider than a narrow card.
        static func banner() -> NSView {
            let banner = NSHostingView(rootView: Text(verbatim: String(repeating: "This link was already open. ", count: 8))
                .lineLimit(1).fixedSize())
            banner.sizingOptions = [.intrinsicContentSize]
            banner.isHidden = true
            return banner
        }

        /// Like the Command bar: a hidden overlay holding a 600 pt panel centred in its top part.
        static func commandBar() -> NSView {
            let overlay = NSView()
            overlay.isHidden = true
            let panel = NSHostingView(rootView: Color.clear.frame(width: 600, height: 56))
            panel.sizingOptions = [.intrinsicContentSize]
            panel.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.topAnchor.constraint(equalTo: overlay.topAnchor, constant: 100),
                panel.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
                panel.widthAnchor.constraint(lessThanOrEqualTo: overlay.widthAnchor, constant: -24),
            ])
            return overlay
        }

        func layOut() {
            window.contentView?.layoutSubtreeIfNeeded()
        }

        func resize(width: CGFloat) {
            window.setContentSize(NSSize(width: width, height: 800))
            layOut()
        }

        func close() {
            host.show(nil)
            window.close()
        }

        /// A page that fills its viewport, shown in the card the way the window shows a Tab.
        func load() async throws -> WKWebView {
            let page = context.makePage(for: TabID())
            try page.load(#require(URL(string: "data:text/html,<body style='margin:0'>fit</body>")), httpsFirst: false)
            host.show(page.webView)
            layOut()
            try await waitUntilAsync("the page has loaded") {
                (try? await page.webView.evaluateJavaScript("document.readyState")) as? String == "complete"
            }
            return page.webView
        }

        func expectPageFillsCard(_ webView: WKWebView, sourceLocation: SourceLocation = #_sourceLocation) async throws {
            let card = canvas.cardFrame
            let frame = canvas.convert(webView.bounds, from: webView)
            #expect(card.width > 0, sourceLocation: sourceLocation)
            #expect(frame == card, "the web view's frame is the card's inner bounds", sourceLocation: sourceLocation)
            let width = Int(card.width.rounded())
            try await waitUntilAsync("the page lays out at the card's width") {
                (try? await webView.evaluateJavaScript("window.innerWidth")) as? Int == width
            }
            let innerWidth = try await webView.evaluateJavaScript("window.innerWidth") as? Int
            #expect(innerWidth == width, "window.innerWidth is the card's width", sourceLocation: sourceLocation)
        }
    }
}
