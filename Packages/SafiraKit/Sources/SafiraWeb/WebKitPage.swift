// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
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
    public var onLoadFailure: (@MainActor (LoadFailure) -> Void)?
    public var onContinueOverHTTP: (@MainActor () -> Void)?
    public var onNonWebLink: (@MainActor (NonWebLink) -> Void)?
    public var onDidClose: (@MainActor () -> Void)?
    private var isPlayingMedia = false
    /// The warning the page currently shows; only its own "Continue over HTTP" link is intercepted.
    private var showing: InsecureConnectionWarning?
    private var httpsFirstAddress: URL?
    /// What to ask WebKit for on an HTTPS-first navigation. Tests set `.keepAsRequested` to stand for the cases where
    /// WebKit ignores the preference (system configuration, known hosts), which is when Safira's own page takes over.
    var httpsFirstPolicy: WKWebpagePreferences.UpgradeToHTTPSPolicy = .userMediatedFallbackToHTTP
    /// Lets tests trust a throwaway certificate; nil in the app, where the system decides.
    var trustsServer: (@MainActor (SecTrust) -> Bool)?
    private var sensitiveHistory = SensitiveHistory<ObjectIdentifier>()
    /// Sensitive content seen while the page had no back-forward entry to hold it; it stays for the page's lifetime.
    private var unattributedSensitiveContent: SensitiveContent = []
    private var mainFrameIsPosting = false
    private var observations: [NSKeyValueObservation] = []
    private let makeNewTabPage: @MainActor (WKWebViewConfiguration) -> (TabID, WebKitPage)?
    private let makePopupPage: @MainActor (WKWebViewConfiguration) -> (PopupID, WebKitPage)?
    private let decidePermission: @MainActor (SiteOrigin, [PermissionKind]) async -> PermissionDecision
    private let startDownload: @MainActor (WKDownload) -> Void
    private let onClose: @MainActor () -> Void
    private let navigationDiagnostics: NavigationDiagnostics?

    init(configuration: WKWebViewConfiguration, diagnostics: DiagnosticLogger? = nil,
         makeNewTabPage: @escaping @MainActor (WKWebViewConfiguration) -> (TabID, WebKitPage)?,
         makePopupPage: @escaping @MainActor (WKWebViewConfiguration) -> (PopupID, WebKitPage)?,
         decidePermission: @escaping @MainActor (SiteOrigin, [PermissionKind]) async -> PermissionDecision,
         startDownload: @escaping @MainActor (WKDownload) -> Void,
         onClose: @escaping @MainActor () -> Void) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.makeNewTabPage = makeNewTabPage
        self.makePopupPage = makePopupPage
        self.decidePermission = decidePermission
        self.startDownload = startDownload
        // Public API: the page shows in Safari's Develop menu. Safira has no in-app inspector (ADR 0001).
        webView.isInspectable = true
        self.onClose = onClose
        navigationDiagnostics = diagnostics.map(NavigationDiagnostics.init)
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

    public var navigationState: Data? {
        webView.interactionState as? Data
    }

    public var sensitiveContent: SensitiveContent {
        let list = webView.backForwardList
        let entries = list.backList + [list.currentItem].compactMap { $0 } + list.forwardList
        return sensitiveHistory.content(of: entries.map(ObjectIdentifier.init)).union(unattributedSensitiveContent)
    }

    public func load(_ url: URL, httpsFirst: Bool) {
        httpsFirstAddress = httpsFirst ? url : nil
        showing = nil
        if url.isFileURL {
            // A local page can read only itself: Safira holds no access to the folder around it.
            webView.loadFileURL(url, allowingReadAccessTo: url)
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    /// WebKit navigates to the restored entry right away; a state it cannot read leaves the page without an entry.
    public func restore(_ navigationState: Data) -> Bool {
        webView.interactionState = navigationState
        return webView.backForwardList.currentItem != nil
    }

    public func showInsecureConnectionWarning(_ warning: InsecureConnectionWarning) {
        showing = warning
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
        onNewTab = nil
        onLoadFailure = nil
        onContinueOverHTTP = nil
        onNonWebLink = nil
        onDidClose = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        onClose()
    }

    /// A frame of the shown page has a password field.
    func passwordFieldFound() {
        markShownEntry(.passwordField)
    }

    /// The link a request would open in another app, if WebKit cannot show its scheme itself.
    private func nonWebLink(in request: URLRequest) -> NonWebLink? {
        guard let url = request.url, let scheme = url.scheme?.lowercased(), !WKWebView.handlesURLScheme(scheme) else {
            return nil
        }
        return NonWebLink(url)
    }

    private func markShownEntry(_ content: SensitiveContent) {
        if let entry = webView.backForwardList.currentItem {
            sensitiveHistory.mark(ObjectIdentifier(entry), content)
        } else {
            unattributedSensitiveContent.formUnion(content)
        }
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
                        preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        // First, so that a ⌘-click on a mailto link opens no empty Tab. Every frame and every kind of navigation gets
        // here (click, script, form, redirect), and returning .cancel is what stops WebKit from handing the link to
        // the system: only the session's confirmation may open an app.
        if let link = nonWebLink(in: navigationAction.request) {
            onNonWebLink?(link)
            return (.cancel, preferences)
        }
        // A link the page marks `download` is saved, even with ⌘ held: opening a Tab for it would leave the Tab blank.
        if navigationAction.shouldPerformDownload {
            return (.download, preferences)
        }
        if navigationAction.navigationType == .linkActivated, navigationAction.modifierFlags.contains(.command),
           let url = navigationAction.request.url, let onNewTab {
            onNewTab(.address(url))
            return (.cancel, preferences)
        }
        if navigationAction.navigationType == .linkActivated, let warning = showing,
           navigationAction.request.url == warning.httpURL {
            onContinueOverHTTP?()
            return (.cancel, preferences)
        }
        if navigationAction.request.httpMethod?.uppercased() == "POST", let frame = navigationAction.targetFrame {
            // A main-frame POST gets its own back-forward entry when it commits; a frame's POST lands in the shown one.
            if frame.isMainFrame {
                mainFrameIsPosting = true
            } else {
                markShownEntry(.postBody)
            }
        }
        if navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url,
           let expected = httpsFirstAddress, HTTPSFallback.isSameAddress(url, expected) {
            preferences.preferredHTTPSNavigationPolicy = httpsFirstPolicy
        }
        return (.allow, preferences)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async
        -> WKNavigationResponsePolicy {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        guard DownloadPolicy.savesResponse(canShowType: navigationResponse.canShowMIMEType, contentDisposition: disposition)
        else { return .allow }
        // The POST that produced the file never commits a page, so it must not mark the next page that does.
        if navigationResponse.isForMainFrame { mainFrameIsPosting = false }
        return .download
    }

    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        startDownload(download)
    }

    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        startDownload(download)
    }

    public func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let trustsServer, challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust, trustsServer(trust)
        else { return (.performDefaultHandling, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    // WebKit holds one navigation delegate per web view, so this page is it and hands the load events to the
    // diagnostics, which only observe.
    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if mainFrameIsPosting {
            mainFrameIsPosting = false
            markShownEntry(.postBody)
        }
        navigationDiagnostics?.webView(webView, didCommit: navigation)
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationDiagnostics?.webView(webView, didFinish: navigation)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        navigationDiagnostics?.webView(webView, didFail: navigation, withError: error)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                        withError error: any Error) {
        mainFrameIsPosting = false
        navigationDiagnostics?.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
        let error = error as NSError
        guard let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL else { return }
        onLoadFailure?(LoadFailure(url: url, domain: error.domain, code: error.code))
    }
}

extension WebKitPage: WKUIDelegate {
    /// WebKit requires the returned view to be built from `configuration`, a copy of this page's: the new Tab or popup
    /// keeps the Profile's data store, and a popup keeps `window.opener`. A scripted `window.open` with dimensions
    /// opens a popup; every other request (`target=_blank`, `window.open` without features) opens a background Tab.
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // `window.open("mailto:…")` must not leave a blank Tab or popup behind.
        if let link = nonWebLink(in: navigationAction.request) {
            onNonWebLink?(link)
            return nil
        }
        guard let onNewTab else { return nil }
        let requested = RequestedWindow(width: windowFeatures.width?.doubleValue,
                                        height: windowFeatures.height?.doubleValue)
        if requested.opensFloatingPanel {
            guard let (id, page) = makePopupPage(configuration) else { return nil }
            onNewTab(.popup(id, page, requested))
            return page.webView
        }
        guard let (id, page) = makeNewTabPage(configuration) else { return nil }
        onNewTab(.page(id, page))
        return page.webView
    }

    /// `window.close()` from a page a script opened.
    public func webViewDidClose(_ webView: WKWebView) {
        onDidClose?()
    }

    public func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                        initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        let kinds: [PermissionKind] = switch type {
        case .camera: [.camera]
        case .microphone: [.microphone]
        case .cameraAndMicrophone: [.camera, .microphone]
        @unknown default: []
        }
        return await decide(kinds, for: origin)
    }

    public func webView(_ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin,
                        initiatedBy frame: WKFrameInfo) async -> WKPermissionDecision {
        await decide([.location], for: origin)
    }

    /// WebKit is never left to ask by itself: the answer is the Profile's remembered decision or the user's.
    private func decide(_ kinds: [PermissionKind], for origin: WKSecurityOrigin) async -> WKPermissionDecision {
        guard let origin = SiteOrigin(origin) else { return .deny }
        return await decidePermission(origin, kinds) == .allow ? .grant : .deny
    }
}

extension SiteOrigin {
    @MainActor
    init?(_ origin: WKSecurityOrigin) {
        self.init(scheme: origin.protocol, host: origin.host, port: origin.port)
    }
}
