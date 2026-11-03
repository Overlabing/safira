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
    @ObservationIgnored private var page: (any WebPageHandle)?
    @ObservationIgnored private let makePage: @MainActor (TabID) -> any WebPageHandle

    init(id: TabID, makePage: @escaping @MainActor (TabID) -> any WebPageHandle) {
        self.id = id
        self.makePage = makePage
    }

    public var address: URL? { state.url }

    func load(_ url: URL) {
        let page = page ?? attachPage()
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
        page?.close()
        page = nil
    }

    private func attachPage() -> any WebPageHandle {
        let page = makePage(id)
        page.onStateChange = { [weak self] state in self?.state = state }
        state = page.state
        self.page = page
        return page
    }
}
