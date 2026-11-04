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
    /// Audio or video is playing in the page. WebKit reports media playback as a whole, not sound alone.
    public var isPlayingMedia: Bool

    public init(url: URL? = nil, title: String? = nil, canGoBack: Bool = false, canGoForward: Bool = false,
                isLoading: Bool = false, isPlayingMedia: Bool = false) {
        self.url = url
        self.title = title
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
        self.isPlayingMedia = isPlayingMedia
    }
}

/// A page asking for a new page next to it: a link for a background Tab of the same Profile, or a popup.
public enum NewTabRequest {
    /// A link opened with ⌘: the session builds the Tab's page like any other page of the Profile.
    case address(URL)
    /// A page the web engine built itself for a `target=_blank` link, already registered under this Tab identifier.
    case page(TabID, any WebPageHandle)
    /// A page the web engine built itself for a scripted `window.open` with window features. It is not a Tab: the
    /// session keeps it as a `Popup` of the Tab that opened it.
    case popup(PopupID, any WebPageHandle, RequestedWindow)
}

/// The web page behind a Tab. SafiraWeb backs it with a `WKWebView`; tests use a simulated page.
@MainActor
public protocol WebPageHandle: AnyObject {
    var state: PageState { get }
    /// Called whenever the page's state changes, including navigations the page starts itself (a clicked link).
    var onStateChange: (@MainActor (PageState) -> Void)? { get set }
    /// Called when the page opens a link in a new Tab.
    var onNewTab: (@MainActor (NewTabRequest) -> Void)? { get set }
    /// Called when the page closes its own window with `window.close()`.
    var onDidClose: (@MainActor () -> Void)? { get set }
    /// Called when a top-level navigation fails before any content arrives, unless the page handled the failure itself.
    var onLoadFailure: (@MainActor (LoadFailure) -> Void)? { get set }
    /// Called when the user chooses, on the page shown by `showInsecureConnectionWarning`, to continue over HTTP.
    var onContinueOverHTTP: (@MainActor () -> Void)? { get set }
    /// The engine's opaque navigation state (back-forward list, scroll positions, form fields); nil when it has none.
    var navigationState: Data? { get }
    /// What the pages of the back-forward list hold that keeps the navigation state off the disk (decision D1).
    var sensitiveContent: SensitiveContent { get }
    /// - Parameter httpsFirst: the address was typed without a scheme; the page asks the platform to try HTTPS first.
    func load(_ url: URL, httpsFirst: Bool)
    /// Restores a navigation state taken from `navigationState`; false when the engine could not use it.
    func restore(_ navigationState: Data) -> Bool
    /// Replaces the page with a warning that offers to continue over HTTP, without touching the network.
    func showInsecureConnectionWarning(_ warning: InsecureConnectionWarning)
    func goBack()
    func goForward()
    func reload()
    /// Stops the page for good; the handle is not used afterwards.
    func close()
}
