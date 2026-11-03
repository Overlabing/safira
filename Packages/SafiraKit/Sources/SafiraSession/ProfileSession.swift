// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore

/// Where the Command bar sends what is typed in it.
public enum CommandBarTarget: Hashable, Sendable {
    /// The selected Tab, or a new Tab when none is selected (⌘L).
    case selectedTab
    /// A new Tab, created only when the text is submitted (⌘T).
    case newTab
}

/// The navigation facade of one Profile: its Tabs, the selection, and every navigation the user asks for.
/// It reaches web pages only through `WebPageHandle`, so it runs headless with simulated pages.
@MainActor
@Observable
public final class ProfileSession {
    public private(set) var profile: Profile
    /// The Tabs of the Profile's single Space, in sidebar order.
    public private(set) var tabs: [Tab] = []
    public private(set) var selectedTabID: TabID?
    /// Nil while the Command bar is closed.
    public private(set) var commandBarTarget: CommandBarTarget?
    /// A search typed while the Profile has no search engine; the user is asked to pick one before it runs.
    public private(set) var searchAwaitingEngine: String?
    /// The Tabs closed during this session, the last one closed at the end. Kept in memory only.
    private var closedTabs: [ClosedTab] = []
    @ObservationIgnored private var searchAwaitingEngineTarget = CommandBarTarget.selectedTab
    @ObservationIgnored private let makePage: @MainActor (TabID) -> any WebPageHandle

    private struct ClosedTab {
        let address: URL
        let index: Int
    }

    /// - Parameter makePage: builds the page of a Tab, called once per Tab on its first load.
    public init(profile: Profile, makePage: @escaping @MainActor (TabID) -> any WebPageHandle) {
        self.profile = profile
        self.makePage = makePage
    }

    public var selectedTab: Tab? {
        tabs.first { $0.id == selectedTabID }
    }

    public var canReopenClosedTab: Bool {
        !closedTabs.isEmpty
    }

    // MARK: Tabs

    @discardableResult
    public func openNewTab() -> TabID {
        let tab = makeTab(id: TabID())
        tabs.append(tab)
        selectedTabID = tab.id
        return tab.id
    }

    public func select(_ id: TabID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedTabID = id
    }

    /// Selects the Tab `offset` places away from the selected one, wrapping around the ends of the list.
    public func selectTab(offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let count = tabs.count
        selectedTabID = tabs[((index + offset) % count + count) % count].id
    }

    /// Closing discards the Tab and its page; a Tab that had an address can be reopened during this session.
    /// Closing the selected Tab selects the one that takes its place, or the one before it when it was last.
    /// Closing the last Tab leaves the Profile with no Tab; the window stays open.
    public func close(_ id: TabID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: index)
        if let address = tab.address {
            closedTabs.append(ClosedTab(address: address, index: index))
        }
        tab.close()
        if selectedTabID == id {
            selectedTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    public func closeSelectedTab() {
        if let selectedTabID { close(selectedTabID) }
    }

    /// Reopens the last closed Tab at its former place, loads its last address and selects it.
    @discardableResult
    public func reopenClosedTab() -> TabID? {
        guard let closed = closedTabs.popLast() else { return nil }
        let tab = makeTab(id: TabID())
        tabs.insert(tab, at: min(closed.index, tabs.count))
        selectedTabID = tab.id
        tab.load(closed.address)
        return tab.id
    }

    /// Moves a Tab so that it ends at `index` in the list; an index past either end is clamped to it.
    public func move(_ id: TabID, to index: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: max(0, min(index, tabs.count)))
    }

    /// Moves a Tab `offset` places up (negative) or down (positive), stopping at the ends of the list.
    public func move(_ id: TabID, by offset: Int) {
        guard let from = tabs.firstIndex(where: { $0.id == id }) else { return }
        move(id, to: from + offset)
    }

    // MARK: Command bar

    public func openCommandBar(for target: CommandBarTarget) {
        commandBarTarget = target
    }

    /// Closes the Command bar without opening anything: after ⌘T, no Tab is created.
    public func dismissCommandBar() {
        commandBarTarget = nil
    }

    /// Opens what was typed in the Command bar where its target says, then closes it. With the Command bar closed,
    /// the text goes to the selected Tab.
    public func submitCommandBar(_ text: String) {
        let target = commandBarTarget ?? .selectedTab
        guard let input = CommandBarInput(text) else { return }
        commandBarTarget = nil
        switch input {
        case .address(let url):
            open(url, in: target)
        case .search(let query):
            if let engine = profile.searchEngine {
                open(engine.searchURL(for: query), in: target)
            } else {
                searchAwaitingEngine = query
                searchAwaitingEngineTarget = target
            }
        }
    }

    /// Sets the Profile's search engine and runs the search that was waiting for it.
    public func chooseSearchEngine(_ engine: SearchEngine) {
        profile.searchEngine = engine
        guard let query = searchAwaitingEngine else { return }
        searchAwaitingEngine = nil
        open(engine.searchURL(for: query), in: searchAwaitingEngineTarget)
    }

    public func cancelSearchEngineChoice() {
        searchAwaitingEngine = nil
    }

    // MARK: Navigation

    public func goBack() {
        selectedTab?.goBack()
    }

    public func goForward() {
        selectedTab?.goForward()
    }

    public func reload() {
        selectedTab?.reload()
    }

    private func open(_ url: URL, in target: CommandBarTarget) {
        if target == .newTab || selectedTab == nil {
            openNewTab()
        }
        selectedTab?.load(url)
    }

    /// A page opened a link in a new Tab: it goes to the end of the list, in the background.
    private func openBackgroundTab(_ request: NewTabRequest) {
        switch request {
        case .address(let url):
            let tab = makeTab(id: TabID())
            tabs.append(tab)
            tab.load(url)
        case .page(let id, let page):
            tabs.append(makeTab(id: id, page: page))
        }
    }

    private func makeTab(id: TabID, page: (any WebPageHandle)? = nil) -> Tab {
        Tab(id: id, page: page, makePage: makePage) { [weak self] request in
            self?.openBackgroundTab(request)
        }
    }
}
