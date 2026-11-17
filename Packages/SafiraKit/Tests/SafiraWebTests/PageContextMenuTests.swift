// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
@testable import SafiraWeb
import TestSupport
import Testing
import WebKit

/// Each WebKit item that needs the app maps to Safira's action and to the address it works on (#131).
@Suite struct PageMenuActionTests {
    private let hit = PageHit(link: URL(string: "https://a.example/file.zip")!, image: URL(string: "https://a.example/i.png")!,
                              media: URL(string: "https://a.example/v.mp4")!, frame: URL(string: "https://f.example/")!)

    @Test func eachItemMapsToItsActionAndAddress() {
        let expected: [(String, PageMenuAction, String, Bool)] = [
            ("WKMenuItemIdentifierDownloadImage", .downloadImage, "https://a.example/i.png", true),
            ("WKMenuItemIdentifierDownloadLinkedFile", .downloadLinkedFile, "https://a.example/file.zip", true),
            ("WKMenuItemIdentifierDownloadMedia", .downloadMedia, "https://a.example/v.mp4", true),
            ("WKMenuItemIdentifierOpenLinkInNewWindow", .openLinkInNewTab, "https://a.example/file.zip", false),
            ("WKMenuItemIdentifierOpenImageInNewWindow", .openImageInNewTab, "https://a.example/i.png", false),
            ("WKMenuItemIdentifierOpenMediaInNewWindow", .openMediaInNewTab, "https://a.example/v.mp4", false),
            ("WKMenuItemIdentifierOpenFrameInNewWindow", .openFrameInNewTab, "https://f.example/", false),
        ]
        for (identifier, action, url, isDownload) in expected {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(identifier)
            #expect(PageMenuAction(item: item) == action)
            #expect(action.url(in: hit)?.absoluteString == url)
            #expect(action.isDownload == isDownload)
        }
    }

    @Test func itemsWebKitHandlesItselfAreLeftAlone() {
        for identifier in ["WKMenuItemIdentifierCopyImage", "WKMenuItemIdentifierCopyLink", "WKMenuItemIdentifierLookUp",
                           "WKMenuItemIdentifierShareMenu", "WKMenuItemIdentifierOpenLink"] {
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.identifier = NSUserInterfaceItemIdentifier(identifier)
            #expect(PageMenuAction(item: item) == nil)
        }
    }

    @Test func onlyAnHTTPOrHTTPSAddressStartsADownload() {
        for address in ["data:image/png;base64,AAAA", "blob:https://a.example/1234", "file:///tmp/i.png"] {
            let hit = PageHit(link: URL(string: address)!, image: URL(string: address)!, media: URL(string: address)!)
            #expect(PageMenuAction.downloadImage.url(in: hit) == nil, "\(address)")
            #expect(PageMenuAction.downloadLinkedFile.url(in: hit) == nil, "\(address)")
            #expect(PageMenuAction.downloadMedia.url(in: hit) == nil, "\(address)")
            #expect(PageMenuAction.openImageInNewTab.url(in: hit)?.absoluteString == address)
        }
        let web = PageHit(image: URL(string: "http://a.example/i.png")!)
        #expect(PageMenuAction.downloadImage.url(in: web)?.absoluteString == "http://a.example/i.png")
    }

    @MainActor @Test func aMenuWithNoKnownWebKitItemIsNoticed() {
        let known = NSMenu()
        let copy = NSMenuItem(title: "Copy", action: nil, keyEquivalent: "")
        copy.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierCopy")
        let submenu = NSMenu()
        submenu.addItem(copy)
        let parent = NSMenuItem(title: "More", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        known.addItem(parent)
        #expect(!PageMenuAction.hasNoKnownItem(known))

        let renamed = NSMenu()
        let item = NSMenuItem(title: "Download Image", action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierSaveImageV2")
        renamed.addItem(item)
        #expect(PageMenuAction.hasNoKnownItem(renamed))
    }

    @Test func aHitReadsOnlyWebAddresses() {
        let read = PageHit(["link": "javascript:alert(1)", "image": "https://a.example/i.png", "frame": "about:blank"])
        #expect(read == PageHit(image: URL(string: "https://a.example/i.png")!))
    }
}

/// Download Image and Open Link in New Tab on a real page, through the real WebKit. The menu is built here with WebKit's
/// identifiers, since a test cannot open the real one; the point is read from the page as a right-click reads it.
@MainActor
@Suite(.serialized, .oneWebKitTestAtATime) struct PageContextMenuTests {
    private func menu(_ action: PageMenuAction) -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: "WebKit's title", action: nil, keyEquivalent: "")
        item.identifier = NSUserInterfaceItemIdentifier(action.rawValue)
        menu.addItem(item)
        return menu
    }

    private func choose(_ action: PageMenuAction, at css: NSPoint, in webView: SafiraWebView) async throws -> NSMenu {
        let point = NSPoint(x: css.x, y: webView.isFlipped ? css.y : webView.bounds.height - css.y)
        webView.startHitTest(at: point)
        try await waitUntil("the point is read") { webView.hasFinishedHitTest }
        let menu = menu(action)
        webView.retarget(menu)
        if !menu.items.isEmpty { menu.performActionForItem(at: 0) }
        return menu
    }

    /// The menu opens before the page answers, and that first answer finds nothing (the page was busy): the item is
    /// kept, and choosing it reads the point again and downloads.
    @Test func anItemChosenBeforeThePageAnswersStillDownloads() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: StoreLayout(root: root))
            defer { ids = registry.profiles.map(\.id) }
            let profile = registry.active
            profile.web.downloadsDirectory = root.appending(path: "Downloads", directoryHint: .isDirectory)
            profile.session.submitCommandBar(server.url("/image.html").absoluteString)
            let tab = try #require(profile.session.selectedTabID)
            let webView = try #require(profile.web.webView(for: tab) as? SafiraWebView)
            let window = TestWindow.host(webView, width: 600, height: 400)
            defer { window.close() }
            try await waitUntil("the page loads") { webView.url == server.url("/image.html") && !webView.isLoading }

            let gate = Gate()
            let real = webView.readPage
            var reads = 0
            webView.readPage = { view, script, arguments in
                reads += 1
                if reads == 1 {
                    await gate.wait()
                    return nil
                }
                return await real(view, script, arguments)
            }
            let point = NSPoint(x: 50, y: webView.isFlipped ? 50 : webView.bounds.height - 50)
            webView.startHitTest(at: point)
            let menu = menu(.downloadImage)
            webView.retarget(menu)
            #expect(!webView.hasFinishedHitTest)
            #expect(menu.items.count == 1)
            menu.performActionForItem(at: 0)
            gate.open()
            try await waitUntil("the image is saved") { profile.downloads.all.first?.state == .completed }
            #expect(profile.downloads.all.first?.sourceURL == server.url("/photo.png"))
            #expect(reads == 2)
        }
        for id in ids { await removeDataStoreWhenReleased(id) }
    }

    @Test func downloadImageSavesTheImageInTheTabsProfile() async throws {
        let server = try await DownloadServer.start()
        defer { server.stop() }
        let root = FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        var ids: [ProfileID] = []
        do {
            let registry = ProfileRegistry(layout: StoreLayout(root: root))
            defer { ids = registry.profiles.map(\.id) }
            let profile = registry.active
            profile.web.downloadsDirectory = root.appending(path: "Downloads", directoryHint: .isDirectory)
            profile.session.submitCommandBar(server.url("/image.html").absoluteString)
            let tab = try #require(profile.session.selectedTabID)
            let webView = try #require(profile.web.webView(for: tab) as? SafiraWebView)
            let window = TestWindow.host(webView, width: 600, height: 400)
            defer { window.close() }
            try await waitUntil("the page loads") { webView.url == server.url("/image.html") && !webView.isLoading }

            let menu = try await choose(.downloadImage, at: NSPoint(x: 50, y: 50), in: webView)
            #expect(menu.items.count == 1)
            try await waitUntil("the image is saved") {
                profile.downloads.all.first?.state == .completed
            }
            let saved = try #require(profile.downloads.all.first)
            #expect(saved.sourceURL == server.url("/photo.png"))
            #expect(saved.receivedBytes == 1000)

            let tabs = profile.session.tabs.count
            let opened = try await choose(.openLinkInNewTab, at: NSPoint(x: 250, y: 50), in: webView)
            #expect(opened.items.first?.title == "Open Link in New Tab")
            try await waitUntil("a Tab opens") { profile.session.tabs.count == tabs + 1 }
            let index = try #require(profile.session.tabs.firstIndex { $0.id == tab })
            #expect(profile.session.tabs[index + 1].address == server.url("/page.html"))
            #expect(profile.session.selectedTabID == tab)

            let nothing = try await choose(.downloadImage, at: NSPoint(x: 450, y: 300), in: webView)
            #expect(nothing.items.isEmpty)
        }
        for id in ids { await removeDataStoreWhenReleased(id) }
    }
}

/// Holds a reading back until the test lets it go.
@MainActor
private final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

