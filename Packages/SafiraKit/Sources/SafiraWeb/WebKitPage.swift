// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import WebKit

/// A Tab's page backed by a `WKWebView`. Its view is owned here, never by the views that show it, so taking it out
/// of the window and putting it back does not reload it.
@MainActor
public final class WebKitPage: WebPageHandle {
    public let webView: WKWebView
    public var onStateChange: (@MainActor (PageState) -> Void)?
    public var onLoadFailure: (@MainActor (LoadFailure) -> Void)?
    public var onContinueOverHTTP: (@MainActor () -> Void)?
    let navigationHandler = PageNavigationDelegate()
    private var observations: [NSKeyValueObservation] = []
    private let onClose: @MainActor () -> Void

    init(configuration: WKWebViewConfiguration, onClose: @escaping @MainActor () -> Void) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.onClose = onClose
        navigationHandler.page = self
        webView.navigationDelegate = navigationHandler
        observations = [
            observe(\.url), observe(\.title), observe(\.canGoBack), observe(\.canGoForward), observe(\.isLoading),
        ]
    }

    public var state: PageState {
        PageState(url: webView.url, title: webView.title, canGoBack: webView.canGoBack,
                  canGoForward: webView.canGoForward, isLoading: webView.isLoading)
    }

    public func load(_ url: URL, httpsFirst: Bool) {
        navigationHandler.expectHTTPSFirst(url, enabled: httpsFirst)
        webView.load(URLRequest(url: url))
    }

    public func showInsecureConnectionWarning(_ warning: InsecureConnectionWarning) {
        navigationHandler.showing = warning
        // The failed address stays the page's address, so the Command bar and reload still name the site.
        webView.loadHTMLString(InsecureConnectionPage.html(for: warning), baseURL: warning.failedURL)
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
        onLoadFailure = nil
        onContinueOverHTTP = nil
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

/// Keeps the navigation delegate out of `WebKitPage`'s public surface.
@MainActor
final class PageNavigationDelegate: NSObject, WKNavigationDelegate {
    weak var page: WebKitPage?
    /// The warning the page currently shows; only its own "Continue over HTTP" link is intercepted.
    var showing: InsecureConnectionWarning?
    private var httpsFirstAddress: URL?
    /// What to ask WebKit for on an HTTPS-first navigation. Tests set `.keepAsRequested` to stand for the cases where
    /// WebKit ignores the preference (system configuration, known hosts), which is when Safira's own page takes over.
    var httpsFirstPolicy: WKWebpagePreferences.UpgradeToHTTPSPolicy = .userMediatedFallbackToHTTP
    /// Lets tests trust a throwaway certificate; nil in the app, where the system decides.
    var trustsServer: (@MainActor (SecTrust) -> Bool)?

    func expectHTTPSFirst(_ url: URL, enabled: Bool) {
        httpsFirstAddress = enabled ? url : nil
        showing = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        if navigationAction.navigationType == .linkActivated, let warning = showing,
           navigationAction.request.url == warning.httpURL {
            page?.onContinueOverHTTP?()
            return (.cancel, preferences)
        }
        if navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url,
           let expected = httpsFirstAddress, HTTPSFallback.isSameAddress(url, expected) {
            preferences.preferredHTTPSNavigationPolicy = httpsFirstPolicy
        }
        return (.allow, preferences)
    }

    func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let trustsServer, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust, trustsServer(trust)
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        let error = error as NSError
        guard let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL else { return }
        page?.onLoadFailure?(LoadFailure(url: url, domain: error.domain, code: error.code))
    }
}
