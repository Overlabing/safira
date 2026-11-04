// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore
import SafiraStore

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
    public let profileID: ProfileID
    /// The Profile's own settings; they are saved with its Tabs.
    public private(set) var settings: ProfileSettings
    /// The Profile's Spaces, in sidebar order; never empty.
    public private(set) var spaces: [Space]
    public private(set) var activeSpaceID: SpaceID
    /// Nil while the Command bar is closed.
    public private(set) var commandBarTarget: CommandBarTarget?
    /// A search typed while the Profile has no search engine; the user is asked to pick one before it runs.
    public private(set) var searchAwaitingEngine: String?
    /// The windows pages opened with window features (sign-in popups), oldest first. They are not Tabs and are never saved.
    public private(set) var popups: [Popup] = []
    /// The Tabs closed during this session, the last one closed at the end. Kept in memory only.
    private var closedTabs: [ClosedTab] = []
    @ObservationIgnored private var searchAwaitingEngineTarget = CommandBarTarget.selectedTab
    @ObservationIgnored private let makePage: @MainActor (TabID) -> any WebPageHandle
    @ObservationIgnored private let osBuild: String
    /// False for a Private window's session: its one Space is internal, never shown, and no other can be added.
    public let hasSpaces: Bool
    /// Nil for a session that keeps no history, as a Private window's does.
    @ObservationIgnored let history: ProfileDatabase?
    @ObservationIgnored private let historyRecorder: HistoryRecorder?
    /// Called when the Profile's history could not be written or searched.
    @ObservationIgnored public var onHistoryError: (@MainActor (any Error) -> Void)? {
        didSet { historyRecorder?.onError = onHistoryError }
    }

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
    ///   - history: the Profile's database, where the pages its Tabs visit are recorded and searched; nil keeps no history.
    ///   - hasSpaces: false for a Private window, which has a single internal Space the user never sees.
    ///   - makePage: builds the page of a Tab, called once per Tab on its first load or its first selection.
    public init(profileID: ProfileID, settings: ProfileSettings = ProfileSettings(), osBuild: String = OSBuild.current,
                history: ProfileDatabase? = nil, hasSpaces: Bool = true,
                makePage: @escaping @MainActor (TabID) -> any WebPageHandle) {
        self.profileID = profileID
        self.settings = settings
        self.osBuild = osBuild
        self.hasSpaces = hasSpaces
        self.history = history
        historyRecorder = history.map(HistoryRecorder.init(database:))
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
        popups.forEach { $0.close() }
        popups = []
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
        let restored = Tab(restoring: record, osBuild: osBuild, makePage: makePage) { [weak self] request in
            self?.openBackgroundTab(request, after: record.id)
        }
        observeVisits(of: restored)
        return restored
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
        _ = (activeSpaceID, settings)
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

    /// Adds a Space after the others and makes it active. It starts with no Tab. A session without Spaces adds none and
    /// answers its only one.
    @discardableResult
    public func createSpace(name: String, emoji: String) -> SpaceID {
        guard hasSpaces else { return activeSpaceID }
        let space = Space(id: SpaceID(), name: Self.cleanName(name) ?? Self.initialSpaceName,
                          emoji: Self.cleanEmoji(emoji) ?? Self.initialSpaceEmoji)
        spaces.append(space)
        activeSpaceID = space.id
        return space.id
    }

    /// Renames a Space. A blank name or emoji keeps the current one; an emoji keeps its first character only.
    public func renameSpace(_ id: SpaceID, name: String, emoji: String) {
        guard hasSpaces, let space = space(id) else { return }
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
        closePopups(openedBy: space.allTabs.map(\.id))
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

    /// Opens a link another app sent as a new Tab, selected, in the Space that was last active (the one shown when the
    /// Profile was last used, saved with it).
    @discardableResult
    public func openExternalLink(_ url: URL) -> TabID {
        let id = openNewTab()
        selectedTab?.load(url)
        return id
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
        closePopups(openedBy: [id])
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

    /// Closes every Tab of every Space for good, releasing their pages; none can be reopened. For a Profile being
    /// deleted.
    public func closeAllTabs() {
        popups.forEach { $0.close() }
        popups = []
        allTabs.forEach { $0.close() }
        for space in spaces {
            space.tabs = []
            space.selectedTabID = nil
        }
        closedTabs = []
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

    /// Moves a Tab to the end of another Space of this Profile, keeping its page. A Space of another Profile is not
    /// one of `spaces`, so the move is refused: a Tab never leaves its Profile. Returns whether the Tab moved.
    @discardableResult
    public func move(_ id: TabID, toSpace target: SpaceID) -> Bool {
        guard let destination = space(target),
              let source = spaces.first(where: { $0.tabs.contains { $0.id == id } }),
              source.id != target,
              let index = source.tabs.firstIndex(where: { $0.id == id }) else { return false }
        let tab = source.tabs.remove(at: index)
        destination.tabs.append(tab)
        if source.selectedTabID == id {
            source.selectedTabID = source.tabs.isEmpty ? nil : source.tabs[min(index, source.tabs.count - 1)].id
            if source.id == activeSpaceID { source.selectedTab?.wake() }
        }
        if destination.selectedTabID == nil { destination.selectedTabID = id }
        return true
    }

    /// Moves a Tab `offset` places up (negative) or down (positive), stopping at the ends of the list. Places are
    /// counted in Tabs: a Pinned tab takes the place of the Tab it passes, whatever Folders sit between them.
    public func move(_ id: TabID, by offset: Int) {
        guard let siblings = siblings(of: id), let from = siblings.firstIndex(of: id) else { return }
        let space = activeSpace
        guard space.holds(.tab(id)) else {
            move(id, to: from + offset)
            return
        }
        let target = siblings[max(0, min(from + offset, siblings.count - 1))]
        let container = space.container(of: .tab(id))?.id
        guard let index = space.items(in: container)?.firstIndex(where: { $0.id == .tab(target) }) else { return }
        movePinned(.tab(id), into: container, at: index)
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

    /// Moves a Pinned tab or a Folder to the place right before another pinned item, in the pinned area or Folder that
    /// holds it. Refused like `movePinned(_:into:at:)`, and when both are the same item.
    @discardableResult
    public func movePinned(_ item: PinnedItemID, before target: PinnedItemID) -> Bool {
        guard item != target, let space = spaces.first(where: { $0.holds(target) }), space.holds(item) else { return false }
        let container = space.container(of: target)?.id
        let others = (space.items(in: container) ?? []).filter { $0.id != item }
        guard let index = others.firstIndex(where: { $0.id == target }) else { return false }
        return movePinned(item, into: container, at: index)
    }

    private func folder(_ id: FolderID) -> Folder? {
        spaces.lazy.compactMap { $0.folder(id) }.first
    }

    // MARK: Popups

    /// Closes a popup and its page, as the user does with its close button.
    public func closePopup(_ id: PopupID) {
        guard let index = popups.firstIndex(where: { $0.id == id }) else { return }
        popups.remove(at: index).close()
    }

    private func closePopups(openedBy tabs: [TabID]) {
        popups.filter { tabs.contains($0.openerTabID) }.forEach { closePopup($0.id) }
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
            if let engine = settings.searchEngine {
                open(engine.searchURL(for: query), in: target)
            } else {
                searchAwaitingEngine = query
                searchAwaitingEngineTarget = target
            }
        }
    }

    /// Sets the Profile's search engine and runs the search that was waiting for it.
    public func chooseSearchEngine(_ engine: SearchEngine) {
        settings.searchEngine = engine
        guard let query = searchAwaitingEngine else { return }
        searchAwaitingEngine = nil
        open(engine.searchURL(for: query), in: searchAwaitingEngineTarget)
    }

    public func cancelSearchEngineChoice() {
        searchAwaitingEngine = nil
    }

    /// Opens a suggestion where the Command bar's target says, then closes the Command bar. An open Tab is shown, in
    /// whichever Space of this Profile holds it, and no Tab is created even after ⌘T.
    public func openSuggestion(_ suggestion: CommandBarSuggestion) {
        let target = commandBarTarget ?? .selectedTab
        commandBarTarget = nil
        switch suggestion.kind {
        case .openTab(let id):
            select(id)
        case .history(let url):
            open(url, in: target)
        }
    }

    // MARK: Settings

    /// Pages created from now on follow the new settings; pages already open keep theirs.
    public func setWebContentSettings(_ webContent: WebContentSettings) {
        settings.webContent = webContent
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
    /// opener's Space. A popup is not a Tab: it stays a window of the Tab that opened it.
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
        case .popup(let id, let page, let requested):
            let popup = Popup(id: id, openerTabID: opener, requestedWindow: requested, page: page)
            popup.attach(onClose: { [weak self] in self?.closePopup(id) },
                         onNewTab: { [weak self] request in self?.openBackgroundTab(request, after: opener) })
            popups.append(popup)
        }
    }

    /// Selects a Tab of the active Space. A Tab shown for the first time since a relaunch creates its page here.
    private func setSelection(_ id: TabID?) {
        activeSpace.selectedTabID = id
        selectedTab?.wake()
    }

    private func makeTab(id: TabID, page: (any WebPageHandle)? = nil) -> Tab {
        let tab = Tab(id: id, page: page, osBuild: osBuild, makePage: makePage) { [weak self] request in
            self?.openBackgroundTab(request, after: id)
        }
        observeVisits(of: tab)
        return tab
    }

    /// Returns once the visits recorded so far have reached the history database.
    public func recordedHistorySettled() async {
        await historyRecorder?.settled()
    }

    private func observeVisits(of tab: Tab) {
        guard let historyRecorder else { return }
        tab.onVisitEvent = { [unowned historyRecorder] in historyRecorder.record($0) }
    }
}
