// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraSession
import WebKit

/// A Tab's page backed by a `WKWebView`. Its view is owned here, never by the views that show it, so taking it out
/// of the window and putting it back does not reload it.
@MainActor
public final class WebKitPage: WebPageHandle {
    public let webView: WKWebView
    public var onStateChange: (@MainActor (PageState) -> Void)?
    private var observations: [NSKeyValueObservation] = []
    private let onClose: @MainActor () -> Void

    init(configuration: WKWebViewConfiguration, onClose: @escaping @MainActor () -> Void) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.onClose = onClose
        observations = [
            observe(\.url), observe(\.title), observe(\.canGoBack), observe(\.canGoForward), observe(\.isLoading),
        ]
    }

    public var state: PageState {
        PageState(url: webView.url, title: webView.title, canGoBack: webView.canGoBack,
                  canGoForward: webView.canGoForward, isLoading: webView.isLoading)
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
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        onClose()
    }

    private func observe<Value>(_ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
        webView.observe(keyPath) { [weak self] _, _ in
            // WebKit reports its key-value changes on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onStateChange?(self.state)
            }
        }
    }
}
