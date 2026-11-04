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

    /// The Tabs of the active Space that are not pinned, in sidebar order.
    public var tabs: [Tab] {
        activeSpace.tabs
    }

    /// The active Space's pinned area: its Pinned tabs and Folders, in order.
    public var pinnedItems: [PinnedItem] {
        activeSpace.pinned
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

    /// Replaces the Spaces with saved ones, as at launch, and closes the Tabs open before. The selected Tab of the
    /// active Space and every Pinned tab of the Profile get a page, since a Profile's Pinned tabs reload when it is
    /// shown; every other Tab stays dormant until it is shown. A save with no Space changes nothing.
    public func restore(_ saved: SavedSession) {
        guard let active = saved.activeSpace else { return }
        allTabs.forEach { $0.close() }
        spaces = saved.spaces.map { record in
            let space = Space(id: record.id, name: record.name, emoji: record.emoji, paletteID: record.paletteID)
            space.pinned = record.pinned.map(restoredItem)
            space.tabs = record.tabs.map { restoredTab($0) }
            space.selectedTabID = record.selectedTabID ?? space.allTabs.first?.id
            return space
        }
        activeSpaceID = active.id
        allTabs.filter(\.isPinned).forEach { $0.wake() }
        activeSpace.selectedTab?.wake()
    }

    /// What to save of the Profile's Spaces and Tabs now.
    public func savedSession() -> SavedSession {
        SavedSession(spaces: spaces.map(\.record), activeSpaceID: activeSpaceID)
    }

    private func restoredTab(_ record: TabRecord) -> Tab {
        Tab(restoring: record, osBuild: osBuild, makePage: makePage) { [weak self] request in
            self?.openBackgroundTab(request, after: record.id)
        }
    }

    private func restoredItem(_ record: PinnedItemRecord) -> PinnedItem {
        switch record {
        case .tab(let tab):
            let restored = restoredTab(tab)
            restored.restorePinned()
            return .tab(restored)
        case .folder(let folder):
            return .folder(Folder(id: folder.id, name: folder.name, isExpanded: folder.isExpanded,
                                  items: folder.items.map(restoredItem)))
        }
    }

    /// Reads what `savedSession()` depends on, so that observing this call reports every change worth saving.
    func readSavedFields() {
        _ = activeSpaceID
        for space in spaces {
            _ = (space.name, space.emoji, space.paletteID, space.selectedTabID, space.pinned.count)
            for folder in space.folders {
                _ = (folder.name, folder.isExpanded, folder.items.count)
            }
            for tab in space.allTabs {
                _ = (tab.state, tab.dormantRecord, tab.isPinned, tab.pinnedAddress)
            }
        }
    }

    /// Every Tab of every Space.
    var allTabs: [Tab] {
        spaces.flatMap(\.allTabs)
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
        space.allTabs.forEach { $0.close() }
        space.tabs = []
        space.pinned = []
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
        guard let space = spaces.first(where: { $0.allTabs.contains { $0.id == id } }) else { return }
        activeSpaceID = space.id
        setSelection(id)
    }

    /// Selects the Tab `offset` places away from the selected one, wrapping around the ends of the list. The list is
    /// the Space's Pinned tabs, folded Folders included, then its other Tabs.
    public func selectTab(offset: Int) {
        let order = activeSpace.allTabs
        guard let index = order.firstIndex(where: { $0.id == selectedTabID }) else { return }
        let count = order.count
        setSelection(order[((index + offset) % count + count) % count].id)
    }

    /// Closing discards the Tab and its page; a Tab that had an address can be reopened during this session.
    /// Closing a Pinned tab only drops its page: it stays pinned, shows its last address and loads it again when it is
    /// next selected. Closing the selected Tab selects the one that takes its place, or the one before it when it was
    /// last. Closing the last Tab leaves the Profile with no selected Tab; the window stays open.
    public func close(_ id: TabID) {
        guard let space = spaces.first(where: { $0.allTabs.contains { $0.id == id } }),
              let position = space.allTabs.firstIndex(where: { $0.id == id }) else { return }
        if let index = space.tabs.firstIndex(where: { $0.id == id }) {
            let tab = space.tabs.remove(at: index)
            if let address = tab.address {
                closedTabs.append(ClosedTab(address: address, space: space.id, index: index))
            }
            tab.close()
        } else {
            space.pinnedTabs.first { $0.id == id }?.unload()
        }
        if space.selectedTabID == id {
            let remaining = space.allTabs.filter { $0.id != id }
            space.selectedTabID = remaining.isEmpty ? nil : remaining[min(position, remaining.count - 1)].id
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

    /// Moves a Tab so that it ends at `index` in its list; an index past either end is clamped to it. A Pinned tab
    /// moves inside the pinned area or Folder that holds it.
    public func move(_ id: TabID, to index: Int) {
        let space = activeSpace
        if space.holds(.tab(id)) {
            movePinned(.tab(id), into: space.container(of: .tab(id))?.id, at: index)
            return
        }
        guard let from = space.tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = space.tabs.remove(at: from)
        space.tabs.insert(tab, at: max(0, min(index, space.tabs.count)))
    }

    /// Moves a Tab `offset` places up (negative) or down (positive), stopping at the ends of the list.
    public func move(_ id: TabID, by offset: Int) {
        guard let from = siblings(of: id)?.firstIndex(where: { $0 == id }) else { return }
        move(id, to: from + offset)
    }

    /// Whether `move(_:by:)` would change anything.
    public func canMove(_ id: TabID, by offset: Int) -> Bool {
        guard let siblings = siblings(of: id), let from = siblings.firstIndex(of: id) else { return false }
        return siblings.indices.contains(from + offset)
    }

    /// The Tabs next to a Tab of the active Space, itself included, in order: the plain Tabs, or what its Folder or the
    /// pinned area holds around it. Folders do not count, they are not Tabs.
    private func siblings(of id: TabID) -> [TabID]? {
        let space = activeSpace
        if space.holds(.tab(id)) {
            return space.items(in: space.container(of: .tab(id))?.id)?.map(\.id).compactMap { item in
                if case .tab(let tab) = item { tab } else { nil }
            }
        }
        return space.tabs.contains { $0.id == id } ? space.tabs.map(\.id) : nil
    }

    // MARK: Pinned tabs and Folders

    /// Pins a Tab: it leaves the other Tabs for the end of its Space's pinned area, remembers its address and keeps
    /// its page and its selection. False when the Tab is not a plain Tab of a Space.
    @discardableResult
    public func pin(_ id: TabID) -> Bool {
        guard let space = spaces.first(where: { $0.tabs.contains { $0.id == id } }),
              let index = space.tabs.firstIndex(where: { $0.id == id }) else { return false }
        let tab = space.tabs.remove(at: index)
        tab.pin()
        space.pinned.append(.tab(tab))
        return true
    }

    /// Unpins a Tab: it leaves the pinned area or its Folder and becomes the first of the Space's other Tabs, right
    /// below the pinned area. False when the Tab is not a Pinned tab.
    @discardableResult
    public func unpin(_ id: TabID) -> Bool {
        guard let space = spaces.first(where: { $0.holds(.tab(id)) }),
              case .tab(let tab)? = space.remove(.tab(id)) else { return false }
        tab.unpin()
        space.tabs.insert(tab, at: 0)
        return true
    }

    /// Pins a plain Tab or unpins a Pinned tab.
    public func togglePin(_ id: TabID) {
        if !unpin(id) { pin(id) }
    }

    public func toggleSelectedTabPin() {
        if let selectedTabID { togglePin(selectedTabID) }
    }

    /// Adds an empty, expanded Folder at the end of the pinned area of the active Space, or of the Folder `parent`.
    /// A blank name becomes "New Folder". Nil when `parent` is not a Folder.
    @discardableResult
    public func createFolder(name: String, in parent: FolderID? = nil) -> FolderID? {
        let space = parent.map { parent in spaces.first { $0.folder(parent) != nil } } ?? activeSpace
        guard let space, var items = space.items(in: parent) else { return nil }
        let folder = Folder(id: FolderID(), name: Self.cleanName(name) ?? Self.initialFolderName)
        items.append(.folder(folder))
        space.setItems(items, in: parent)
        return folder.id
    }

    public static let initialFolderName = "New Folder"

    /// Renames a Folder. A blank name keeps the current one.
    public func renameFolder(_ id: FolderID, name: String) {
        guard let name = Self.cleanName(name) else { return }
        folder(id)?.name = name
    }

    public func setFolderExpanded(_ id: FolderID, _ isExpanded: Bool) {
        folder(id)?.isExpanded = isExpanded
    }

    /// Deletes a Folder. What it held is not lost: it takes the Folder's place, in the same order.
    public func deleteFolder(_ id: FolderID) {
        guard let space = spaces.first(where: { $0.folder(id) != nil }), let folder = space.folder(id) else { return }
        let owner = space.container(of: .folder(id))?.id
        guard var items = space.items(in: owner),
              let index = items.firstIndex(where: { $0.id == .folder(id) }) else { return }
        items.replaceSubrange(index...index, with: folder.items)
        space.setItems(items, in: owner)
    }

    /// Moves a Pinned tab or a Folder so that it ends at `index` of the pinned area, or of the Folder `folder`; an
    /// index past either end is clamped to it, and nil puts it last. False, and nothing moves, when the item is not
    /// pinned (a plain Tab can neither enter a Folder nor be placed in the pinned area this way: it must be pinned
    /// first), when the Folder is not in the item's Space, or when it is the item itself or inside it.
    @discardableResult
    public func movePinned(_ item: PinnedItemID, into folder: FolderID?, at index: Int? = nil) -> Bool {
        guard let space = spaces.first(where: { $0.holds(item) }) else { return false }
        if let folder {
            guard space.folder(folder) != nil else { return false }
            if case .folder(let moving) = item, space.folder(moving)?.contains(folder: folder) == true { return false }
        }
        guard let moved = space.remove(item), var items = space.items(in: folder) else { return false }
        items.insert(moved, at: max(0, min(index ?? items.count, items.count)))
        space.setItems(items, in: folder)
        return true
    }

    private func folder(_ id: FolderID) -> Folder? {
        spaces.lazy.compactMap { $0.folder(id) }.first
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
        case .address(let url, let scheme):
            open(url, in: target, httpsFirst: scheme == .defaultedToHTTPS)
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

    private func open(_ url: URL, in target: CommandBarTarget, httpsFirst: Bool = false) {
        if target == .newTab || selectedTab == nil {
            openNewTab()
        }
        selectedTab?.load(url, httpsFirst: httpsFirst)
    }

    /// A page opened a link in a new Tab: it goes right after the Tab that opened it, in the background, in the
    /// opener's Space.
    private func openBackgroundTab(_ request: NewTabRequest, after opener: TabID) {
        let space = spaces.first { $0.allTabs.contains { $0.id == opener } } ?? activeSpace
        // A link opened from a Pinned tab goes to the top of the other Tabs, right below the pinned area.
        let position = space.tabs.firstIndex { $0.id == opener }.map { $0 + 1 }
            ?? (space.holds(.tab(opener)) ? 0 : space.tabs.count)
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
