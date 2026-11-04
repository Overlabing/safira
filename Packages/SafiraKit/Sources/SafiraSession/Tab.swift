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

    func reload() {
        page?.reload()
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
        page?.close()
        page = nil
    }

    @discardableResult
    private func attach(_ page: any WebPageHandle) -> any WebPageHandle {
        page.onStateChange = { [weak self] state in self?.pageChanged(state) }
        page.onNewTab = { [onNewTab] request in onNewTab(request) }
        page.onLoadFailure = { [weak self] failure in self?.pageFailed(failure) }
        page.onContinueOverHTTP = { [weak self] in self?.continueOverHTTP() }
        page.onNonWebLink = { [weak self] link in self?.onNonWebLink?(link, self?.state.url?.host) }
        self.page = page
        pageChanged(page.state)
        return page
    }

    private func pageChanged(_ state: PageState) {
        self.state = state
        // The warning page borrows the address that failed to load; that address was never visited.
        guard insecureConnectionWarning == nil else { return }
        for event in visits.observe(state, sensitiveContent: page?.sensitiveContent ?? []) {
            onVisitEvent?(event)
        }
    }
}
