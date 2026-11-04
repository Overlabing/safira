// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Observation
import SafiraCore

/// A window a page opened with `window.open` and window features, typically a sign-in. It belongs to the Tab that
/// opened it and ends when its page closes itself, when the user closes it, or when that Tab closes. The page was built
/// by the web engine from the opener's configuration, so it shares the opener's Profile data store.
@MainActor
@Observable
public final class Popup: Identifiable {
    public let id: PopupID
    public let openerTabID: TabID
    public let requestedWindow: RequestedWindow
    public private(set) var state: PageState
    public private(set) var isClosed = false
    @ObservationIgnored let page: any WebPageHandle

    init(id: PopupID, openerTabID: TabID, requestedWindow: RequestedWindow, page: any WebPageHandle) {
        self.id = id
        self.openerTabID = openerTabID
        self.requestedWindow = requestedWindow
        self.page = page
        state = page.state
    }

    func attach(onClose: @escaping @MainActor () -> Void, onNewTab: @escaping @MainActor (NewTabRequest) -> Void,
                onNonWebLink: @escaping @MainActor (NonWebLink, String?) -> Void) {
        page.onStateChange = { [weak self] state in self?.state = state }
        page.onDidClose = onClose
        page.onNewTab = onNewTab
        page.onNonWebLink = { [weak self] link in onNonWebLink(link, self?.state.url?.host) }
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        page.onStateChange = nil
        page.onDidClose = nil
        page.onNewTab = nil
        page.onNonWebLink = nil
        page.close()
    }
}
