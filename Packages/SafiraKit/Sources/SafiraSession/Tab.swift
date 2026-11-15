// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore

/// One open web page. A new Tab creates its page on its first load, unless the web engine built it. A Tab restored
/// after a relaunch stays dormant, with its saved address and title and no page, until it is first selected.
@MainActor
@Observable
public final class Tab: Identifiable {
    public let id: TabID
    public private(set) var state = PageState()
    /// The saved record of a restored Tab that has no page yet.
    public private(set) var dormantRecord: TabRecord?
    /// Set from the moment an address typed without a scheme cannot be opened securely until the Tab loads anything else.
    public private(set) var insecureConnectionWarning: InsecureConnectionWarning?
    /// Whether the Tab sits in its Space's pinned area. Only the Space's `ProfileSession` pins and unpins.
    public private(set) var isPinned = false
    /// The address the Tab was pinned at; nil while it is not pinned or was pinned blank.
    public private(set) var pinnedAddress: URL?
    /// How large the page is drawn: its site's remembered zoom, or 100%.
    public private(set) var zoom = PageZoom.actualSize
    /// Where the Tab stands after its page's content process ended (a crash, or memory pressure).
    public private(set) var crash = PageCrash.none
    /// The address the page showed when its process ended; leaving it gives the page a new automatic reload.
    @ObservationIgnored private var crashedAddress: URL?
    @ObservationIgnored private var page: (any WebPageHandle)?
    @ObservationIgnored private let osBuild: String
    /// The address of the last HTTPS-first navigation: only its failure may lead to a warning.
    @ObservationIgnored private var httpsFirstAddress: URL?
    @ObservationIgnored private let makePage: @MainActor (TabID) -> any WebPageHandle
    @ObservationIgnored private let onNewTab: @MainActor (NewTabRequest) -> Void
    @ObservationIgnored private var visits = VisitTracker()
    /// Called when the Tab visits a web address or learns the title of the page it shows; the session sets it.
    @ObservationIgnored var onVisitEvent: (@MainActor (VisitEvent) -> Void)?
    /// Called when the Tab's page follows a non-web link, with the host of the page that asked; the session sets it.
    @ObservationIgnored var onNonWebLink: (@MainActor (NonWebLink, String?) -> Void)?
    /// Called when the Tab's page finished loading, with its icon links and the page to fetch them through; the
    /// session sets it. A dormant Tab has no page, so it never fetches.
    @ObservationIgnored var onIconLinks: (@MainActor (PageIconLinks, any SiteResourceFetcher) -> Void)?
    /// Called when a download starts in a Tab that has never shown anything; the session sets it on Tabs a link opened.
    @ObservationIgnored var onEmptyDownload: (@MainActor () -> Void)?
    /// The zoom remembered for an address's site; the session sets it with `followZoom(_:)`.
    @ObservationIgnored private var siteZoom: (@MainActor (URL?) -> PageZoom)?
    /// The site whose zoom the page has; a navigation to another site takes that site's.
    @ObservationIgnored private var zoomedSite: ZoomSite?

    init(id: TabID, page: (any WebPageHandle)? = nil, osBuild: String,
         makePage: @escaping @MainActor (TabID) -> any WebPageHandle,
         onNewTab: @escaping @MainActor (NewTabRequest) -> Void) {
        self.id = id
        self.osBuild = osBuild
        self.makePage = makePage
        self.onNewTab = onNewTab
        if let page {
            attach(page)
        }
    }

    /// A restored Tab: it shows its saved address and title and creates no page.
    init(restoring record: TabRecord, osBuild: String, makePage: @escaping @MainActor (TabID) -> any WebPageHandle,
         onNewTab: @escaping @MainActor (NewTabRequest) -> Void) {
        self.id = record.id
        self.osBuild = osBuild
        self.makePage = makePage
        self.onNewTab = onNewTab
        state = PageState(url: record.address, title: record.title)
        dormantRecord = record
        pinnedAddress = record.pinnedAddress
        visits = VisitTracker(restoredAddress: record.address)
    }

    public var address: URL? { state.url }

    /// What is saved of this Tab. A dormant Tab keeps its record as it was restored.
    var record: TabRecord {
        var record: TabRecord
        if let dormantRecord {
            record = dormantRecord
        } else {
            let navigationState = page.flatMap {
                NavigationStateRule.savable($0.navigationState, sensitiveContent: $0.sensitiveContent)
            }
            record = TabRecord(id: id, address: state.url, title: state.title, navigationState: navigationState,
                               navigationStateOSBuild: navigationState == nil ? nil : osBuild)
        }
        record.pinnedAddress = pinnedAddress
        return record
    }

    func pin() {
        isPinned = true
        pinnedAddress = address
    }

    func unpin() {
        isPinned = false
        pinnedAddress = nil
    }

    /// Marks a restored Tab as pinned without changing the address it was pinned at.
    func restorePinned() {
        isPinned = true
    }

    /// Drops the page and keeps the Tab as a restored one: it shows its last address and title, and loads them again
    /// when it is next shown. This is how a Pinned tab is closed.
    func unload() {
        let saved = record
        close()
        crash = .none
        state = PageState(url: state.url, title: state.title)
        dormantRecord = saved
    }

    /// Gives a dormant Tab its page and restores it: its navigation state when it can, otherwise its last address.
    func wake() {
        guard let record = dormantRecord else { return }
        dormantRecord = nil
        let page = attach(makePage(id))
        switch Restoration(record, osBuild: osBuild) {
        case .navigationState(let navigationState, let fallback):
            if !page.restore(navigationState), let fallback {
                page.load(fallback, httpsFirst: false)
            }
        case .address(let url):
            page.load(url, httpsFirst: false)
        case .blank:
            break
        }
    }

    func load(_ url: URL, httpsFirst: Bool = false) {
        dormantRecord = nil
        crash = .none
        let page = page ?? attach(makePage(id))
        insecureConnectionWarning = nil
        httpsFirstAddress = httpsFirst ? url : nil
        page.load(url, httpsFirst: httpsFirst)
    }

    /// The user's explicit choice on the warning: the one way an address typed without a scheme loads over HTTP.
    public func continueOverHTTP() {
        guard let warning = insecureConnectionWarning else { return }
        load(warning.httpURL)
    }

    func goBack() {
        guard state.canGoBack else { return }
        page?.goBack()
    }

    func goForward() {
        guard state.canGoForward else { return }
        page?.goForward()
    }

    /// After a crash, the user's reload is the page's last chance: crashing again shows the crashed state at once.
    func reload() {
        if crash != .none { crash = .reloaded }
        page?.reload()
    }

    /// The window shows this Tab's page now. A page whose process ended while it was out of sight, or just now,
    /// reloads here, once.
    func wasShown() {
        guard crash == .reloadWhenShown, let page else { return }
        crash = .reloaded
        page.reload()
    }

    private func contentProcessEnded() {
        crashedAddress = state.url
        crash = crash.next
    }

    /// Whether the Tab has a page to zoom or search; a dormant or blank Tab has none.
    var hasPage: Bool { page != nil && state.url != nil }

    /// From now on the page takes the zoom of each site it shows.
    func followZoom(_ siteZoom: @escaping @MainActor (URL?) -> PageZoom) {
        self.siteZoom = siteZoom
        zoomedSite = nil
        updateZoom(for: state.url)
    }

    /// Draws the page at `zoom`, for its current site.
    func apply(_ zoom: PageZoom) {
        self.zoom = zoom
        page?.pageZoom = zoom.factor
    }

    private func updateZoom(for url: URL?) {
        guard let siteZoom, page != nil, let site = ZoomSite(url), site != zoomedSite else { return }
        zoomedSite = site
        apply(siteZoom(url))
    }

    func find(_ text: String, backwards: Bool) async -> Bool {
        await page?.find(text, backwards: backwards) ?? false
    }

    func countMatches(of text: String) async -> Int {
        await page?.countMatches(of: text) ?? 0
    }

    func endFind() {
        page?.endFind()
    }

    private func pageFailed(_ failure: LoadFailure) {
        guard let attempted = httpsFirstAddress, HTTPSFallback.isSameAddress(failure.url, attempted),
              let warning = HTTPSFallback.warning(after: failure) else { return }
        httpsFirstAddress = nil
        insecureConnectionWarning = warning
        page?.showInsecureConnectionWarning(warning)
    }

    func close() {
        page?.onStateChange = nil
        page?.onNewTab = nil
        page?.onLoadFailure = nil
        page?.onContinueOverHTTP = nil
        page?.onNonWebLink = nil
        page?.onDownloadStarted = nil
        page?.onIconLinks = nil
        page?.onContentProcessEnded = nil
        page?.close()
        page = nil
        zoomedSite = nil
    }

    @discardableResult
    private func attach(_ page: any WebPageHandle) -> any WebPageHandle {
        page.onStateChange = { [weak self] state in self?.pageChanged(state) }
        page.onNewTab = { [onNewTab] request in onNewTab(request) }
        page.onLoadFailure = { [weak self] failure in self?.pageFailed(failure) }
        page.onContinueOverHTTP = { [weak self] in self?.continueOverHTTP() }
        page.onNonWebLink = { [weak self] link in self?.onNonWebLink?(link, self?.state.url?.host) }
        page.onDownloadStarted = { [weak self] in self?.pageStartedDownload() }
        page.onContentProcessEnded = { [weak self] in self?.contentProcessEnded() }
        page.onIconLinks = { [weak self, weak page] links in
            guard let self, let page else { return }
            onIconLinks?(links, page)
        }
        self.page = page
        pageChanged(page.state)
        return page
    }

    private func pageStartedDownload() {
        guard state.url == nil, !state.canGoBack else { return }
        onEmptyDownload?()
    }

    private func pageChanged(_ state: PageState) {
        self.state = state
        if crash != .none, let url = state.url, url != crashedAddress {
            crash = .none
        }
        updateZoom(for: state.url)
        // The warning page borrows the address that failed to load; that address was never visited.
        guard insecureConnectionWarning == nil else { return }
        for event in visits.observe(state, sensitiveContent: page?.sensitiveContent ?? []) {
            onVisitEvent?(event)
        }
    }
}

/// What a Tab does after its page's content process ended. The page reloads by itself once, when it is shown; if it
/// ends again before the user leaves the address, the Tab shows that the page crashed and waits for a reload.
public enum PageCrash: Hashable, Sendable {
    case none
    /// The process ended; the page reloads the next time the window shows it, at once for the shown Tab.
    case reloadWhenShown
    /// The page reloaded after a crash.
    case reloaded
    /// The page crashed again: the Tab shows "This page crashed" with a Reload button.
    case crashed

    var next: PageCrash {
        switch self {
        case .none, .reloadWhenShown: .reloadWhenShown
        case .reloaded, .crashed: .crashed
        }
    }
}
