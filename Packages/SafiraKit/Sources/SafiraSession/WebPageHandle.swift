// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// What a web page reports about itself; a Tab mirrors it.
public struct PageState: Hashable, Sendable {
    public var url: URL?
    public var title: String?
    public var canGoBack: Bool
    public var canGoForward: Bool
    public var isLoading: Bool

    public init(url: URL? = nil, title: String? = nil, canGoBack: Bool = false, canGoForward: Bool = false,
                isLoading: Bool = false) {
        self.url = url
        self.title = title
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
    }
}

/// The web page behind a Tab. SafiraWeb backs it with a `WKWebView`; tests use a simulated page.
@MainActor
public protocol WebPageHandle: AnyObject {
    var state: PageState { get }
    /// Called whenever the page's state changes, including navigations the page starts itself (a clicked link).
    var onStateChange: (@MainActor (PageState) -> Void)? { get set }
    /// Called when a top-level navigation fails before any content arrives, unless the page handled the failure itself.
    var onLoadFailure: (@MainActor (LoadFailure) -> Void)? { get set }
    /// Called when the user chooses, on the page shown by `showInsecureConnectionWarning`, to continue over HTTP.
    var onContinueOverHTTP: (@MainActor () -> Void)? { get set }
    /// - Parameter httpsFirst: the address was typed without a scheme; the page asks the platform to try HTTPS first.
    func load(_ url: URL, httpsFirst: Bool)
    /// Replaces the page with a warning that offers to continue over HTTP, without touching the network.
    func showInsecureConnectionWarning(_ warning: InsecureConnectionWarning)
    func goBack()
    func goForward()
    func reload()
    /// Stops the page for good; the handle is not used afterwards.
    func close()
}
