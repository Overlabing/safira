// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

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
    func load(_ url: URL)
    func goBack()
    func goForward()
    func reload()
    /// Stops the page for good; the handle is not used afterwards.
    func close()
}
