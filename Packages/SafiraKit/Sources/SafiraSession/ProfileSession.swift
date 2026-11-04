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

/// The navigation facade of one Profile: its Spaces, their Tabs, the selection, and every navigation the user asks
/// for. Tab commands act on the active Space. It reaches web pages only through `WebPageHandle`, so it runs headless
/// with simulated pages.
@MainActor
@Observable
public final class ProfileSession {
    public private(set) var profile: Profile
    /// The Profile's Spaces, in sidebar order; never empty.
    public private(set) var spaces: [Space]
    public private(set) var activeSpaceID: SpaceID
    /// Nil while the Command bar is closed.
    public private(set) var commandBarTarget: CommandBarTarget?
    /// A search typed while the Profile has no search engine; the user is asked to pick one before it runs.
    public private(set) var searchAwaitingEngine: String?
    /// The Tabs closed during this session, the last one closed at the end. Kept in memory only.
    private var closedTabs: [ClosedTab] = []
    @ObservationIgnored private var searchAwaitingEngineTarget = CommandBarTarget.selectedTab
    @ObservationIgnored private let makePage: @MainActor (TabID) -> any WebPageHandle
    @ObservationIgnored private let osBuild: String

    private struct ClosedTab {
        let address: URL
        let space: SpaceID
        let index: Int
    }

    /// The Space a Profile starts with, the same one the database creates.
    public static let initialSpaceName = "Home"
    public static let initialSpaceEmoji = "🏠"

    /// - Parameters:
    ///   - osBuild: the macOS build, which decides whether a saved navigation state can be restored.
    ///   - makePage: builds the page of a Tab, called once per Tab on its first load or its first selection.
    public init(profile: Profile, osBuild: String = OSBuild.current,
                makePage: @escaping @MainActor (TabID) -> any WebPageHandle) {
        self.profile = profile
        self.osBuild = osBuild
        self.makePage = makePage
        let space = Space(id: SpaceID(), name: Self.initialSpaceName, emoji: Self.initialSpaceEmoji)
        spaces = [space]
        activeSpaceID = space.id
    }

    public var activeSpace: Space {
        spaces.first { $0.id == activeSpaceID } ?? spaces[0]
    }

    /// The Tabs of the active Space, in sidebar order.
    public var tabs: [Tab] {
        activeSpace.tabs
    }

    public var selectedTabID: TabID? {
        activeSpace.selectedTabID
    }

    public var selectedTab: Tab? {
        activeSpace.selectedTab
    }

    public var canReopenClosedTab: Bool {
        !closedTabs.isEmpty
    }

    // MARK: Saving and restoring

    /// Replaces the Spaces with saved ones, as at launch, and closes the Tabs open before. Only the selected Tab of
    /// the active Space gets a page; every other Tab stays dormant until it is shown. A save with no Space changes
    /// nothing.
    public func restore(_ saved: SavedSession) {
        guard let active = saved.activeSpace else { return }
        allTabs.forEach { $0.close() }
        spaces = saved.spaces.map { record in
            let space = Space(id: record.id, name: record.name, emoji: record.emoji, paletteID: record.paletteID)
            space.tabs = record.tabs.map { tab in
                Tab(restoring: tab, osBuild: osBuild, makePage: makePage) { [weak self] request in
                    self?.openBackgroundTab(request, after: tab.id)
                }
            }
            space.selectedTabID = record.selectedTabID ?? space.tabs.first?.id
            return space
        }
        activeSpaceID = active.id
        activeSpace.selectedTab?.wake()
    }

    /// What to save of the Profile's Spaces and Tabs now.
    public func savedSession() -> SavedSession {
        SavedSession(spaces: spaces.map(\.record), activeSpaceID: activeSpaceID)
    }

    /// Reads what `savedSession()` depends on, so that observing this call reports every change worth saving.
    func readSavedFields() {
        _ = activeSpaceID
        for space in spaces {
            _ = (space.name, space.emoji, space.paletteID, space.selectedTabID)
            for tab in space.tabs {
                _ = (tab.state, tab.dormantRecord)
            }
        }
    }

    /// Every Tab of every Space.
    var allTabs: [Tab] {
        spaces.flatMap(\.tabs)
    }

    // MARK: Spaces

    /// Adds a Space after the others and makes it active. It starts with no Tab.
    @discardableResult
    public func createSpace(name: String, emoji: String) -> SpaceID {
        let space = Space(id: SpaceID(), name: Self.cleanName(name) ?? Self.initialSpaceName,
                          emoji: Self.cleanEmoji(emoji) ?? Self.initialSpaceEmoji)
        spaces.append(space)
        activeSpaceID = space.id
        return space.id
    }

    /// Renames a Space. A blank name or emoji keeps the current one; an emoji keeps its first character only.
    public func renameSpace(_ id: SpaceID, name: String, emoji: String) {
        guard let space = space(id) else { return }
        if let name = Self.cleanName(name) { space.name = name }
        if let emoji = Self.cleanEmoji(emoji) { space.emoji = emoji }
    }

    /// Moves a Space so that it ends at `index` in the list; an index past either end is clamped to it.
    public func moveSpace(_ id: SpaceID, to index: Int) {
        guard let from = spaces.firstIndex(where: { $0.id == id }) else { return }
        let space = spaces.remove(at: from)
        spaces.insert(space, at: max(0, min(index, spaces.count)))
    }

    /// Moves a Space `offset` places towards the start (negative) or the end (positive), stopping at the ends.
    public func moveSpace(_ id: SpaceID, by offset: Int) {
        guard let from = spaces.firstIndex(where: { $0.id == id }) else { return }
        moveSpace(id, to: from + offset)
    }

    /// Shows a Space: its selected Tab gets a page if it had none.
    public func selectSpace(_ id: SpaceID) {
        guard space(id) != nil else { return }
        activeSpaceID = id
        activeSpace.selectedTab?.wake()
    }

    /// Shows the Space `offset` places away from the active one, wrapping around the ends of the list.
    public func selectSpace(offset: Int) {
        guard let index = spaces.firstIndex(where: { $0.id == activeSpaceID }) else { return }
        let count = spaces.count
        selectSpace(spaces[((index + offset) % count + count) % count].id)
    }

    public var canDeleteSpace: Bool {
        spaces.count > 1
    }

    /// Deletes a Space and closes its Tabs; they cannot be reopened. The Profile's logins and history are untouched:
    /// they belong to the Profile, not to the Space. The last Space of a Profile cannot be deleted. Deleting the
    /// active Space shows the one before it, or the next one when it was first.
    public func deleteSpace(_ id: SpaceID) {
        guard canDeleteSpace, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let space = spaces.remove(at: index)
        space.tabs.forEach { $0.close() }
        space.tabs = []
        if activeSpaceID == id {
            selectSpace(spaces[max(0, index - 1)].id)
        }
    }

    private func space(_ id: SpaceID) -> Space? {
        spaces.first { $0.id == id }
    }

    private static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cleanEmoji(_ emoji: String) -> String? {
        emoji.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)
    }

    // MARK: Tabs

    @discardableResult
    public func openNewTab() -> TabID {
        let tab = makeTab(id: TabID())
        activeSpace.tabs.append(tab)
        setSelection(tab.id)
        return tab.id
    }

    /// Shows a Tab, switching to its Space when it is in another one.
    public func select(_ id: TabID) {
        guard let space = spaces.first(where: { $0.tabs.contains { $0.id == id } }) else { return }
        activeSpaceID = space.id
        setSelection(id)
    }

    /// Selects the Tab `offset` places away from the selected one, wrapping around the ends of the list.
    public func selectTab(offset: Int) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let count = tabs.count
        setSelection(tabs[((index + offset) % count + count) % count].id)
    }

    /// Closing discards the Tab and its page; a Tab that had an address can be reopened during this session.
    /// Closing the selected Tab selects the one that takes its place, or the one before it when it was last.
    /// Closing the last Tab leaves the Profile with no Tab; the window stays open.
    public func close(_ id: TabID) {
        guard let space = spaces.first(where: { $0.tabs.contains { $0.id == id } }),
              let index = space.tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = space.tabs.remove(at: index)
        if let address = tab.address {
            closedTabs.append(ClosedTab(address: address, space: space.id, index: index))
        }
        tab.close()
        if space.selectedTabID == id {
            space.selectedTabID = space.tabs.isEmpty ? nil : space.tabs[min(index, space.tabs.count - 1)].id
            if space.id == activeSpaceID { space.selectedTab?.wake() }
        }
    }

    public func closeSelectedTab() {
        if let selectedTabID { close(selectedTabID) }
    }

    /// Reopens the last closed Tab at its former place in its Space, which it shows, loads its last address and
    /// selects it. A Tab whose Space was deleted since reopens in the active Space.
    @discardableResult
    public func reopenClosedTab() -> TabID? {
        guard let closed = closedTabs.popLast() else { return nil }
        if space(closed.space) != nil {
            activeSpaceID = closed.space
        }
        let tab = makeTab(id: TabID())
        activeSpace.tabs.insert(tab, at: min(closed.index, tabs.count))
        setSelection(tab.id)
        tab.load(closed.address)
        return tab.id
    }

    /// Moves a Tab so that it ends at `index` in the list; an index past either end is clamped to it.
    public func move(_ id: TabID, to index: Int) {
        let space = activeSpace
        guard let from = space.tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = space.tabs.remove(at: from)
        space.tabs.insert(tab, at: max(0, min(index, space.tabs.count)))
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

    /// A page opened a link in a new Tab: it goes right after the Tab that opened it, in the background, in the
    /// opener's Space.
    private func openBackgroundTab(_ request: NewTabRequest, after opener: TabID) {
        let space = spaces.first { $0.tabs.contains { $0.id == opener } } ?? activeSpace
        let position = space.tabs.firstIndex { $0.id == opener }.map { $0 + 1 } ?? space.tabs.count
        switch request {
        case .address(let url):
            let tab = makeTab(id: TabID())
            space.tabs.insert(tab, at: position)
            tab.load(url)
        case .page(let id, let page):
            space.tabs.insert(makeTab(id: id, page: page), at: position)
        }
    }

    /// Selects a Tab of the active Space. A Tab shown for the first time since a relaunch creates its page here.
    private func setSelection(_ id: TabID?) {
        activeSpace.selectedTabID = id
        selectedTab?.wake()
    }

    private func makeTab(id: TabID, page: (any WebPageHandle)? = nil) -> Tab {
        Tab(id: id, page: page, osBuild: osBuild, makePage: makePage) { [weak self] request in
            self?.openBackgroundTab(request, after: id)
        }
    }
}
