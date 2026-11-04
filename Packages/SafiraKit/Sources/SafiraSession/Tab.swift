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
    @ObservationIgnored private var page: (any WebPageHandle)?
    @ObservationIgnored private let osBuild: String
    @ObservationIgnored private let makePage: @MainActor (TabID) -> any WebPageHandle
    @ObservationIgnored private let onNewTab: @MainActor (NewTabRequest) -> Void

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
    }

    public var address: URL? { state.url }

    /// What is saved of this Tab. A dormant Tab keeps its record as it was restored.
    var record: TabRecord {
        if let dormantRecord { return dormantRecord }
        let navigationState = page.flatMap {
            NavigationStateRule.savable($0.navigationState, sensitiveContent: $0.sensitiveContent)
        }
        return TabRecord(id: id, address: state.url, title: state.title, navigationState: navigationState,
                         navigationStateOSBuild: navigationState == nil ? nil : osBuild)
    }

    /// Gives a dormant Tab its page and restores it: its navigation state when it can, otherwise its last address.
    func wake() {
        guard let record = dormantRecord else { return }
        dormantRecord = nil
        let page = attach(makePage(id))
        switch Restoration(record, osBuild: osBuild) {
        case .navigationState(let navigationState, let fallback):
            if !page.restore(navigationState), let fallback {
                page.load(fallback)
            }
        case .address(let url):
            page.load(url)
        case .blank:
            break
        }
    }

    func load(_ url: URL) {
        dormantRecord = nil
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
