// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore
import SafiraSession
import WebKit

/// A Profile's Tab as its extensions see it. What it reports comes from the Tab's own page, so the address an
/// extension trusts (`sender.url`, `tabs.query`) is the page's committed one.
@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    let id: TabID
    private unowned let host: ExtensionHost

    init(id: TabID, host: ExtensionHost) {
        self.id = id
        self.host = host
    }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        host.extensionWindow
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        host.openTabs.firstIndex { $0 === self } ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        host.webView(for: id)
    }

    func title(for context: WKWebExtensionContext) -> String? {
        host.webView(for: id)?.title
    }

    /// The committed address: `WKWebView.url` already shows a navigation that has only started, which an extension
    /// would take for the page's (a password manager matches its logins against `sender.url`).
    func url(for context: WKWebExtensionContext) -> URL? {
        host.webView(for: id)?.backForwardList.currentItem?.url
    }

    func isPinned(for context: WKWebExtensionContext) -> Bool {
        host.sessionTab(id)?.isPinned ?? false
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        host.activeTab === self
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        !(host.webView(for: id)?.isLoading ?? false)
    }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        host.select(id)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        host.close(id)
        completionHandler(nil)
    }
}

/// The Main window as one Profile's extensions see it: that Profile's Tabs only, never another Profile's. A Private
/// window is never one, since it has no extensions.
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    private unowned let host: ExtensionHost

    init(host: ExtensionHost) {
        self.host = host
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        host.openTabs
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        host.activeTab
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType {
        .normal
    }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool {
        false
    }
}
