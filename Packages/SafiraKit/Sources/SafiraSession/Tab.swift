// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore

/// One open web page. Its page is created on the first load, never on selection, unless the web engine built it.
@MainActor
@Observable
public final class Tab: Identifiable {
    public let id: TabID
    public private(set) var state = PageState()
    @ObservationIgnored private var page: (any WebPageHandle)?
    @ObservationIgnored private let makePage: @MainActor (TabID) -> any WebPageHandle
    @ObservationIgnored private let onNewTab: @MainActor (NewTabRequest) -> Void

    init(id: TabID, page: (any WebPageHandle)? = nil, makePage: @escaping @MainActor (TabID) -> any WebPageHandle,
         onNewTab: @escaping @MainActor (NewTabRequest) -> Void) {
        self.id = id
        self.makePage = makePage
        self.onNewTab = onNewTab
        if let page {
            attach(page)
        }
    }

    public var address: URL? { state.url }

    func load(_ url: URL) {
        let page = page ?? attach(makePage(id))
        page.load(url)
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

    func close() {
        page?.onStateChange = nil
        page?.onNewTab = nil
        page?.close()
        page = nil
    }

    @discardableResult
    private func attach(_ page: any WebPageHandle) -> any WebPageHandle {
        page.onStateChange = { [weak self] state in self?.state = state }
        page.onNewTab = { [onNewTab] request in onNewTab(request) }
        state = page.state
        self.page = page
        return page
    }
}
