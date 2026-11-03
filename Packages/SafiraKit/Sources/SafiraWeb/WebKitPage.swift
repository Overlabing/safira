// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import WebKit

/// A Tab's page backed by a `WKWebView`. Its view is owned here, never by the views that show it, so taking it out
/// of the window and putting it back does not reload it.
@MainActor
public final class WebKitPage: NSObject, WebPageHandle {
    public let webView: WKWebView
    public var onStateChange: (@MainActor (PageState) -> Void)?
    public var onNewTab: (@MainActor (NewTabRequest) -> Void)?
    private var isPlayingMedia = false
    private var observations: [NSKeyValueObservation] = []
    private let makeNewTabPage: @MainActor (WKWebViewConfiguration) -> (TabID, WebKitPage)?
    private let onClose: @MainActor () -> Void

    init(configuration: WKWebViewConfiguration,
         makeNewTabPage: @escaping @MainActor (WKWebViewConfiguration) -> (TabID, WebKitPage)?,
         onClose: @escaping @MainActor () -> Void) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.makeNewTabPage = makeNewTabPage
        self.onClose = onClose
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observations = [
            observe(\.url), observe(\.title), observe(\.canGoBack), observe(\.canGoForward), observe(\.isLoading),
        ]
    }

    public var state: PageState {
        PageState(url: webView.url, title: webView.title, canGoBack: webView.canGoBack,
                  canGoForward: webView.canGoForward, isLoading: webView.isLoading, isPlayingMedia: isPlayingMedia)
    }

    public func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    public func goBack() {
        webView.goBack()
    }

    public func goForward() {
        webView.goForward()
    }

    public func reload() {
        webView.reload()
    }

    public func close() {
        observations.forEach { $0.invalidate() }
        observations = []
        onStateChange = nil
        onNewTab = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        onClose()
    }

    func refreshMediaState() {
        webView.requestMediaPlaybackState { [weak self] playback in
            guard let self, isPlayingMedia != (playback == .playing) else { return }
            isPlayingMedia = playback == .playing
            onStateChange?(state)
        }
    }

    private func observe<Value>(_ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        let isAddress = keyPath == \WKWebView.url
        return webView.observe(keyPath) { [weak self] _, _ in
            // WebKit reports its key-value changes on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                // A new document starts with no media, and stopping media by leaving the page sends no event.
                if isAddress, self.isPlayingMedia {
                    self.refreshMediaState()
                }
                self.onStateChange?(self.state)
            }
        }
    }
}

extension WebKitPage: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if navigationAction.navigationType == .linkActivated, navigationAction.modifierFlags.contains(.command),
           let url = navigationAction.request.url, let onNewTab {
            onNewTab(.address(url))
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

extension WebKitPage: WKUIDelegate {
    /// WebKit requires the returned view to be built from `configuration`, a copy of this page's: the new Tab keeps
    /// the Profile's data store.
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let onNewTab, let (id, page) = makeNewTabPage(configuration) else { return nil }
        onNewTab(.page(id, page))
        return page.webView
    }
}
