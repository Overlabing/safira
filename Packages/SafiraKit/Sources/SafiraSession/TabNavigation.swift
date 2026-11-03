// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// The web page behind a Tab. SafiraWeb backs it with a `WKWebView`; tests use a simulated page.
@MainActor
public protocol WebPageHandle: AnyObject {
    func load(_ url: URL)
}

/// The navigation facade of one Tab: every page load goes through it.
@MainActor
public final class TabNavigation {
    public private(set) var address: URL?
    private let page: any WebPageHandle

    public init(page: any WebPageHandle) {
        self.page = page
    }

    public func open(_ url: URL) {
        address = url
        page.load(url)
    }
}
