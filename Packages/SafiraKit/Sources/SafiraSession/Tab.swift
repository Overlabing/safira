// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore

/// One open web page. Its page is created on the first load, never on selection.
@MainActor
@Observable
public final class Tab: Identifiable {
    public let id: TabID
    public private(set) var state = PageState()
    /// Set from the moment an address typed without a scheme cannot be opened securely until the Tab loads anything else.
    public private(set) var insecureConnectionWarning: InsecureConnectionWarning?
    @ObservationIgnored private var page: (any WebPageHandle)?
    /// The address of the last HTTPS-first navigation: only its failure may lead to a warning.
    @ObservationIgnored private var httpsFirstAddress: URL?
    @ObservationIgnored private let makePage: @MainActor (TabID) -> any WebPageHandle

    init(id: TabID, makePage: @escaping @MainActor (TabID) -> any WebPageHandle) {
        self.id = id
        self.makePage = makePage
    }

    public var address: URL? { state.url }

    func load(_ url: URL, httpsFirst: Bool = false) {
        let page = page ?? attachPage()
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
        page?.onLoadFailure = nil
        page?.onContinueOverHTTP = nil
        page?.close()
        page = nil
    }

    private func attachPage() -> any WebPageHandle {
        let page = makePage(id)
        page.onStateChange = { [weak self] state in self?.state = state }
        page.onLoadFailure = { [weak self] failure in self?.pageFailed(failure) }
        page.onContinueOverHTTP = { [weak self] in self?.continueOverHTTP() }
        state = page.state
        self.page = page
        return page
    }
}
