// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore

/// The navigation facade of one Profile: its Tabs, the selection, and every navigation the user asks for.
/// It reaches web pages only through `WebPageHandle`, so it runs headless with simulated pages.
@MainActor
@Observable
public final class ProfileSession {
    public private(set) var profile: Profile
    public private(set) var tabs: [Tab] = []
    public private(set) var selectedTabID: TabID?
    /// A search typed while the Profile has no search engine; the user is asked to pick one before it runs.
    public private(set) var searchAwaitingEngine: String?
    @ObservationIgnored private let makePage: @MainActor (TabID) -> any WebPageHandle

    /// - Parameter makePage: builds the page of a Tab, called once per Tab on its first load.
    public init(profile: Profile, makePage: @escaping @MainActor (TabID) -> any WebPageHandle) {
        self.profile = profile
        self.makePage = makePage
    }

    public var selectedTab: Tab? {
        tabs.first { $0.id == selectedTabID }
    }

    @discardableResult
    public func openNewTab() -> TabID {
        let tab = Tab(id: TabID(), makePage: makePage)
        tabs.append(tab)
        selectedTabID = tab.id
        return tab.id
    }

    public func select(_ id: TabID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    /// Closing the selected Tab selects the one that takes its place, or the one before it when it was last.
    /// Closing the last Tab leaves the Profile with no Tab; the window stays open.
    public func close(_ id: TabID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: index)
        tab.close()
        if selectedTabID == id {
            selectedTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    public func closeSelectedTab() {
        if let selectedTabID { close(selectedTabID) }
    }

    /// Opens what was typed in the Command bar in the selected Tab, or in a new Tab when none is selected.
    public func submitCommandBar(_ text: String) {
        switch CommandBarInput(text) {
        case nil:
            return
        case .address(let url, let scheme):
            open(url, httpsFirst: scheme == .defaultedToHTTPS)
        case .search(let query):
            if let engine = profile.searchEngine {
                open(engine.searchURL(for: query))
            } else {
                searchAwaitingEngine = query
            }
        }
    }

    /// Sets the Profile's search engine and runs the search that was waiting for it.
    public func chooseSearchEngine(_ engine: SearchEngine) {
        profile.searchEngine = engine
        guard let query = searchAwaitingEngine else { return }
        searchAwaitingEngine = nil
        open(engine.searchURL(for: query))
    }

    public func cancelSearchEngineChoice() {
        searchAwaitingEngine = nil
    }

    public func goBack() {
        selectedTab?.goBack()
    }

    public func goForward() {
        selectedTab?.goForward()
    }

    public func reload() {
        selectedTab?.reload()
    }

    private func open(_ url: URL, httpsFirst: Bool = false) {
        if selectedTab == nil {
            openNewTab()
        }
        selectedTab?.load(url, httpsFirst: httpsFirst)
    }
}
