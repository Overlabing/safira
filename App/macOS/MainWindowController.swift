// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import AppKit
import Commands
import SafiraCore
import SafiraSession
import SafiraWeb
import SwiftUI

/// The Main window: AppKit owns the window, the Command bar field and the menu actions; SwiftUI draws the sidebar of
/// Tabs; the page area shows the selected Tab's web view, taken from the Profile's registry, or SwiftUI content when
/// there is no page.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    private let registry: ProfileRegistry
    /// The Active profile's session: every Tab, Space and Command bar action reaches this Profile only.
    private var session: ProfileSession { registry.active.session }
    private var webContext: ProfileWebContext { registry.active.web }
    private let commandBar = NSTextField()
    private let backButton = MainWindowController.toolbarButton(symbol: "chevron.left", label: "Back",
                                                               action: #selector(goBack(_:)))
    private let forwardButton = MainWindowController.toolbarButton(symbol: "chevron.right", label: "Forward",
                                                                  action: #selector(goForward(_:)))
    private let reloadButton = MainWindowController.toolbarButton(symbol: "arrow.clockwise", label: "Reload",
                                                                 action: #selector(reload(_:)))
    private let pageArea = TabHostView()
    private var sidebar: NSViewController?
    private var layout: SidebarLayoutViewController?
    private let compactModeStore = CompactModeStore()
    private var presentation: SidebarPresentation
    private var searchEngineSheet: NSWindow?
    private var spaceSheet: NSWindow?
    private var folderSheet: NSWindow?
    private var profileSheet: NSWindow?
    private var clearSheet: NSWindow?
    private var permissionsSheet: NSWindow?
    private lazy var downloadsWindow = DownloadsWindowController(registry: registry)
    private var popupPanels: [PopupID: PopupPanelController] = [:]
    private var renderedTabID: TabID?
    private var dockIconThemeID: String?
    private lazy var permissionPrompter = PermissionPrompter(
        window: { [weak self] in self?.window },
        profileName: { [weak self] id in self?.registry.profiles.first { $0.id == id }?.name ?? "" })
    private let externalApps = WorkspaceExternalApps()
    private let suggestionModel = CommandBarSuggestionModel()
    private var suggestionHost: CommandBarSuggestionHostingView?
    private var suggestionTask: Task<Void, Never>?
    /// The text the shown suggestions were computed for: Return opens a highlighted one only while the text still is it.
    private var suggestionText: String?
    private let bannerModel = MatchBannerModel()
    private var bannerHost: NSHostingView<MatchBannerBar>?
    private var announcedBannerID: UUID?

    init(registry: ProfileRegistry, shortcuts: ShortcutController) {
        self.registry = registry
        presentation = compactModeStore.load()
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Safira"
        window.shortcuts = shortcuts
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        registry.permissionPrompt = { [unowned self] prompt in await permissionPrompter.ask(prompt) }
        registry.appLinkHandlers = AppLinkHandlers(
            launcher: externalApps,
            prompt: { [unowned self] prompt in await permissionPrompter.confirmOpen(prompt) },
            refusal: { [unowned self] refusal in await permissionPrompter.refuseOpen(refusal) },
            openFailure: { [unowned self] app, _ in await permissionPrompter.reportOpenFailure(of: app) })
        layOut(in: window)
        layout?.apply(presentation, animated: false)
        window.center()
        observeSession()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: Menu actions

    /// Opens the Command bar for a new Tab; the Tab is created only when the user presses Enter.
    @objc func newTab(_ sender: Any?) {
        openCommandBar(for: .newTab, text: "", placeholder: Self.newTabPlaceholder)
    }

    @objc func closeTab(_ sender: Any?) {
        session.closeSelectedTab()
        render()
        if session.selectedTab?.address == nil {
            focusCommandBar(nil)
        }
    }

    @objc func reopenClosedTab(_ sender: Any?) {
        session.reopenClosedTab()
        render()
    }

    @objc func togglePin(_ sender: Any?) {
        session.toggleSelectedTabPin()
    }

    /// Opens the naming sheet for a new Folder at the top of the active Space's pinned area.
    @objc func newFolder(_ sender: Any?) {
        editFolder(creatingIn: nil)
    }

    @objc func focusCommandBar(_ sender: Any?) {
        openCommandBar(for: .selectedTab, text: session.selectedTab?.address?.absoluteString ?? "",
                       placeholder: Self.placeholder)
        commandBar.currentEditor()?.selectAll(nil)
    }

    /// Moves the keyboard focus to the list of Tabs, where the arrow keys select a Tab. In Compact mode it shows the
    /// sidebar first.
    @objc func focusTabList(_ sender: Any?) {
        if presentation.isCompact, !presentation.isRevealed {
            presentation.reveal()
            layout?.apply(presentation, animated: true)
        }
        guard let list = sidebar.flatMap({ Self.firstTableView(in: $0.view) }) else { return }
        window?.makeFirstResponder(list)
    }

    /// Compact mode hides the sidebar and gives the page the full width; the choice is kept across launches.
    @objc func toggleCompactMode(_ sender: Any?) {
        let hadFocus = layout?.sidebarHasFocus == true
        presentation.toggleCompact()
        compactModeStore.save(presentation)
        layout?.apply(presentation, animated: true)
        announce(presentation.isCompact ? String(localized: "Compact mode on, sidebar hidden")
                                        : String(localized: "Compact mode off, sidebar shown"))
        if hadFocus {
            if presentation.isCompact, !showPage() { window?.makeFirstResponder(commandBar) }
            else if !presentation.isCompact { focusTabList(nil) }
        }
    }

    /// Not named `toggleSidebar(_:)`: the split view controller answers that selector itself and would disable the item.
    /// In Compact mode, shows the sidebar over the page with the keyboard focus on its list, or hides it again.
    @objc func toggleRevealedSidebar(_ sender: Any?) {
        presentation.toggleRevealed()
        applyReveal()
    }

    // MARK: Space actions

    /// Opens the Space editor for a new Space; the Space is created only when the user confirms.
    @objc func newSpace(_ sender: Any?) {
        editSpace(nil)
    }

    @objc func renameSpace(_ sender: Any?) {
        editSpace(session.activeSpaceID)
    }

    @objc func deleteSpace(_ sender: Any?) {
        confirmDeletion(of: session.activeSpaceID)
    }

    @objc func showPreviousSpace(_ sender: Any?) {
        session.selectSpace(offset: -1)
    }

    @objc func showNextSpace(_ sender: Any?) {
        session.selectSpace(offset: 1)
    }

    @objc func moveSpaceLeft(_ sender: Any?) {
        session.moveSpace(session.activeSpaceID, by: -1)
    }

    @objc func moveSpaceRight(_ sender: Any?) {
        session.moveSpace(session.activeSpaceID, by: 1)
    }

    // MARK: Profile actions

    /// Opens the Profile editor for a new Profile; it is created only when the user confirms with a search engine.
    @objc func newProfile(_ sender: Any?) {
        editProfile(nil)
    }

    @objc func renameProfile(_ sender: Any?) {
        editProfile(registry.activeProfileID)
    }

    @objc func deleteProfile(_ sender: Any?) {
        confirmDeletion(ofProfile: registry.activeProfileID)
    }

    /// The sites the Active profile remembers a camera, microphone or location decision for.
    @objc func showSitePermissions(_ sender: Any?) {
        guard let window, permissionsSheet == nil else { return }
        let view = SitePermissionsView(profileName: registry.activeProfile.name, permissions: registry.active.permissions) {
            [weak self] in self?.endPermissionsSheet()
        }
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: view))
        permissionsSheet = sheet
        window.beginSheet(sheet)
    }

    /// The Active profile's downloads, in a window of their own.
    @objc func showDownloads(_ sender: Any?) {
        downloadsWindow.showWindow(nil)
    }

    private func endPermissionsSheet() {
        guard let sheet = permissionsSheet else { return }
        window?.endSheet(sheet)
        permissionsSheet = nil
    }

    @objc func clearBrowsingData(_ sender: Any?) {
        askToClearBrowsingData(ofProfile: registry.activeProfileID)
    }

    @objc func showPreviousProfile(_ sender: Any?) {
        switchProfile { $0.selectProfile(offset: -1) }
    }

    @objc func showNextProfile(_ sender: Any?) {
        switchProfile { $0.selectProfile(offset: 1) }
    }

    @objc func moveTabUp(_ sender: Any?) {
        session.selectedTabID.map { session.move($0, by: -1) }
    }

    @objc func moveTabDown(_ sender: Any?) {
        session.selectedTabID.map { session.move($0, by: 1) }
    }

    @objc func goBack(_ sender: Any?) {
        session.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        session.goForward()
    }

    @objc func reload(_ sender: Any?) {
        session.reload()
    }

    @objc func showNextTab(_ sender: Any?) {
        session.selectTab(offset: 1)
    }

    @objc func showPreviousTab(_ sender: Any?) {
        session.selectTab(offset: -1)
    }

    /// These change the Profile's settings: pages created from now on follow them, open pages keep theirs.
    @objc func toggleFraudulentSiteWarning(_ sender: Any?) {
        registry.active.webContentSettings.isFraudulentSiteWarningEnabled.toggle()
    }

    @objc func toggleAutoplayingSound(_ sender: Any?) {
        registry.active.webContentSettings.isAutoplayingSoundAllowed.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let tab = session.selectedTab
        switch menuItem.action {
        case #selector(closeTab(_:)): return tab != nil
        case #selector(reopenClosedTab(_:)): return session.canReopenClosedTab
        case #selector(togglePin(_:)):
            menuItem.title = tab?.isPinned == true ? String(localized: "Unpin Tab") : String(localized: "Pin Tab")
            return tab != nil
        case #selector(moveTabUp(_:)): return tab.map { session.canMove($0.id, by: -1) } ?? false
        case #selector(moveTabDown(_:)): return tab.map { session.canMove($0.id, by: 1) } ?? false
        case #selector(goBack(_:)): return tab?.state.canGoBack == true
        case #selector(goForward(_:)): return tab?.state.canGoForward == true
        case #selector(reload(_:)): return tab?.address != nil
        case #selector(showNextTab(_:)), #selector(showPreviousTab(_:)): return session.activeSpace.allTabs.count > 1
        case #selector(deleteSpace(_:)): return session.canDeleteSpace
        case #selector(deleteProfile(_:)): return registry.canDeleteProfile
        case #selector(showNextProfile(_:)), #selector(showPreviousProfile(_:)): return registry.profiles.count > 1
        case #selector(showNextSpace(_:)), #selector(showPreviousSpace(_:)): return session.spaces.count > 1
        case #selector(moveSpaceLeft(_:)): return session.spaces.first?.id != session.activeSpaceID
        case #selector(moveSpaceRight(_:)): return session.spaces.last?.id != session.activeSpaceID
        case #selector(toggleCompactMode(_:)):
            menuItem.state = presentation.isCompact ? .on : .off
            return true
        case #selector(toggleRevealedSidebar(_:)):
            menuItem.title = presentation.isRevealed ? String(localized: "Hide Sidebar") : String(localized: "Show Sidebar")
            return presentation.isCompact
        case #selector(toggleFraudulentSiteWarning(_:)):
            menuItem.state = registry.active.webContentSettings.isFraudulentSiteWarningEnabled ? .on : .off
            return true
        case #selector(toggleAutoplayingSound(_:)):
            menuItem.state = registry.active.webContentSettings.isAutoplayingSoundAllowed ? .on : .off
            return true
        default: return true
        }
    }

    /// A link from another app was opened as a new Tab, in a Profile that is now the Active profile: brings the Main
    /// window forward on it, with the keyboard in the page.
    func showOpenedLink() {
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        showWindow(nil)
        NSApp.activate()
        session.dismissCommandBar()
        render()
        announce(String(localized: "Profile: \(registry.activeProfile.name)"))
        showPage()
    }

    // MARK: Command bar

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if suggestionText == commandBar.stringValue, let suggestion = suggestionModel.highlighted {
                openSuggestion(suggestion)
                return true
            }
            hideSuggestions()
            session.submitCommandBar(commandBar.stringValue)
            render()
            if session.commandBarTarget == nil {
                showPage()
            }
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard !suggestionModel.suggestions.isEmpty, suggestionText == commandBar.stringValue else { return false }
            suggestionModel.moveDown()
            announceHighlight()
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard !suggestionModel.suggestions.isEmpty, suggestionText == commandBar.stringValue else { return false }
            suggestionModel.moveUp()
            announceHighlight()
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            hideSuggestions()
            focusTabList(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            hideSuggestions()
            session.dismissCommandBar()
            commandBar.placeholderString = Self.placeholder
            commandBar.stringValue = session.selectedTab?.address?.absoluteString ?? ""
            if !showPage() {
                commandBar.currentEditor()?.selectAll(nil)
            }
            return true
        default:
            return false
        }
    }

    /// Typing asks the Active profile for local suggestions: its open Tabs and its history. Nothing leaves the app, and
    /// no page loads until Return.
    func controlTextDidChange(_ notification: Notification) {
        updateSuggestions()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        // Leaving the field abandons a pending new Tab, as Escape does.
        hideSuggestions()
        session.dismissCommandBar()
        commandBar.placeholderString = Self.placeholder
        render()
    }

    private func updateSuggestions() {
        suggestionTask?.cancel()
        let text = commandBar.stringValue
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hideSuggestions()
            return
        }
        // Results go to the Profile that was active when the text was typed, and are dropped if another one is shown by
        // the time they arrive or the text moved on.
        let profile = registry.activeProfileID
        let session = session
        suggestionTask = Task { [weak self] in
            let found = await session.suggestions(for: text)
            guard let self, !Task.isCancelled, registry.activeProfileID == profile,
                  commandBar.stringValue == text, commandBar.currentEditor() != nil else { return }
            suggestionModel.show(found, typing: text)
            suggestionText = text
            suggestionHost?.isHidden = found.isEmpty
            if !found.isEmpty {
                announce(String(AttributedString(localized: "^[\(found.count) suggestion](inflect: true)").characters))
            }
        }
    }

    private func hideSuggestions() {
        suggestionTask?.cancel()
        suggestionTask = nil
        suggestionText = nil
        suggestionModel.clear()
        suggestionHost?.isHidden = true
    }

    private func openSuggestion(_ suggestion: CommandBarSuggestion) {
        hideSuggestions()
        session.openSuggestion(suggestion)
        render()
        if session.commandBarTarget == nil {
            showPage()
        }
    }

    /// The keyboard stays in the text field, so VoiceOver is told which suggestion the arrows reached.
    private func announceHighlight() {
        announce(suggestionModel.highlighted?.title ?? commandBar.stringValue)
    }

    /// Setting the text or the focus ends an edit in progress, which dismisses the Command bar: the target comes last.
    private func openCommandBar(for target: CommandBarTarget, text: String, placeholder: String) {
        commandBar.stringValue = text
        commandBar.placeholderString = placeholder
        window?.makeFirstResponder(commandBar)
        session.openCommandBar(for: target)
    }

    /// Puts the keyboard focus in the selected Tab's page; false when it has none.
    @discardableResult
    private func showPage() -> Bool {
        hideRevealedSidebar()
        guard let tab = session.selectedTab, let webView = webContext.webView(for: tab.id) else { return false }
        return window?.makeFirstResponder(webView) ?? false
    }

    // MARK: Spaces

    private static let newSpaceEmoji = ["🌿", "📚", "💼", "🎨", "🎵", "✈️", "🧪", "⭐️"]

    /// A new Space when `id` is nil, otherwise that Space.
    private func editSpace(_ id: SpaceID?) {
        guard let window, spaceSheet == nil else { return }
        let space = id.flatMap { id in session.spaces.first { $0.id == id } }
        if id != nil, space == nil { return }
        let count = session.spaces.count
        let editor = SpaceEditor(
            title: space == nil ? String(localized: "New Space") : String(localized: "Edit Space"),
            confirmTitle: space == nil ? String(localized: "Create") : String(localized: "Save"),
            name: space?.name ?? String(localized: "Space \(count + 1)"),
            emoji: space?.emoji ?? Self.newSpaceEmoji[count % Self.newSpaceEmoji.count],
            paletteID: space?.paletteID ?? ThemeCatalog.nextID(avoiding: session.spaces.map(\.paletteID)),
            save: { [weak self] name, emoji, paletteID in
                guard let self else { return }
                if let id {
                    session.renameSpace(id, name: name, emoji: emoji, paletteID: paletteID)
                } else {
                    session.createSpace(name: name, emoji: emoji, paletteID: paletteID)
                    focusCommandBar(nil)
                }
                endSpaceSheet()
            },
            cancel: { [weak self] in self?.endSpaceSheet() }
        )
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: editor))
        spaceSheet = sheet
        window.beginSheet(sheet)
    }

    private func endSpaceSheet() {
        guard let sheet = spaceSheet else { return }
        window?.endSheet(sheet)
        spaceSheet = nil
    }

    /// A new Folder when `renaming` is nil, created inside `parent` or at the top of the pinned area; otherwise that
    /// Folder is renamed.
    private func editFolder(creatingIn parent: FolderID?, renaming id: FolderID? = nil) {
        guard let window, folderSheet == nil else { return }
        let existing = id.flatMap { id in session.activeSpace.folder(id) }
        if id != nil, existing == nil { return }
        let editor = FolderEditor(
            title: existing == nil ? String(localized: "New Folder") : String(localized: "Rename Folder"),
            confirmTitle: existing == nil ? String(localized: "Create") : String(localized: "Rename"),
            name: existing?.name ?? String(localized: "New Folder"),
            save: { [weak self] name in
                guard let self else { return }
                if let id {
                    session.renameFolder(id, name: name)
                } else {
                    session.createFolder(name: name, in: parent)
                }
                endFolderSheet()
            },
            cancel: { [weak self] in self?.endFolderSheet() }
        )
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: editor))
        folderSheet = sheet
        window.beginSheet(sheet)
    }

    private func endFolderSheet() {
        guard let sheet = folderSheet else { return }
        window?.endSheet(sheet)
        folderSheet = nil
    }

    /// Deleting a Space closes its Tabs for good, so it is confirmed first. The last Space cannot be deleted.
    private func confirmDeletion(of id: SpaceID) {
        guard let window, session.canDeleteSpace, let space = session.spaces.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete the Space “\(space.name)”?")
        let count = space.allTabs.count
        let tabs = count == 0 ? String(localized: "It has no Tab.")
            : String(AttributedString(localized: "Its ^[\(count) Tab](inflect: true) will close.").characters)
        alert.informativeText = tabs + " " + String(localized: "The Profile's logins and history are kept.")
        alert.addButton(withTitle: String(localized: "Delete Space")).hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.session.deleteSpace(id)
        }
    }

    // MARK: Profiles

    private static let newProfileSymbols = ["💼", "🏡", "🎓", "🧪", "🎨", "🌍", "⭐️", "🛠️"]

    /// Shows another Profile; the keyboard focus goes to its page, or to the Command bar when it has none.
    private func switchProfile(_ change: (ProfileRegistry) -> Void) {
        let before = registry.activeProfileID
        change(registry)
        guard registry.activeProfileID != before else { return }
        hideSuggestions()
        session.dismissCommandBar()
        render()
        announce(String(localized: "Profile: \(registry.activeProfile.name)"))
        if !showPage() { focusCommandBar(nil) }
    }

    /// A new Profile when `id` is nil, otherwise that Profile.
    private func editProfile(_ id: ProfileID?) {
        guard let window, profileSheet == nil else { return }
        let profile = id.flatMap { id in registry.profiles.first { $0.id == id } }
        if id != nil, profile == nil { return }
        let count = registry.profiles.count
        let editor = ProfileEditor(
            title: profile == nil ? String(localized: "New Profile") : String(localized: "Edit Profile"),
            confirmTitle: profile == nil ? String(localized: "Create") : String(localized: "Save"),
            name: profile?.name ?? String(localized: "Profile \(count + 1)"),
            symbol: profile?.symbol ?? Self.newProfileSymbols[count % Self.newProfileSymbols.count],
            paletteID: profile?.paletteID ?? ThemeCatalog.nextID(avoiding: registry.profiles.map(\.paletteID)),
            asksForSearchEngine: profile == nil,
            save: { [weak self] name, symbol, paletteID, engine in
                guard let self else { return }
                if let id {
                    registry.renameProfile(id, name: name, symbol: symbol, paletteID: paletteID)
                } else if let engine {
                    endProfileSheet()
                    switchProfile {
                        $0.createProfile(name: name, symbol: symbol, searchEngine: engine, paletteID: paletteID)
                    }
                    return
                }
                endProfileSheet()
            },
            cancel: { [weak self] in self?.endProfileSheet() }
        )
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: editor))
        profileSheet = sheet
        window.beginSheet(sheet)
    }

    private func endProfileSheet() {
        guard let sheet = profileSheet else { return }
        window?.endSheet(sheet)
        profileSheet = nil
    }

    /// Deleting a Profile erases everything it holds with no way back, so the confirmation names it. The last Profile
    /// cannot be deleted.
    private func confirmDeletion(ofProfile id: ProfileID) {
        guard let window, registry.canDeleteProfile, let profile = registry.profiles.first(where: { $0.id == id })
        else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "Delete the Profile “\(profile.name)”?")
        alert.informativeText = String(localized: """
            Everything “\(profile.name)” holds is erased: its logins, cookies and website data, its history, its \
            Spaces and Tabs, and its settings. This cannot be undone.
            """)
        alert.addButton(withTitle: String(localized: "Delete “\(profile.name)”")).hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            Task { @MainActor in
                let wasActive = self.registry.activeProfileID == id
                do {
                    try await self.registry.deleteProfile(id)
                } catch {
                    self.showDeletionError(error)
                }
                if wasActive {
                    self.announce(String(localized: "Profile: \(self.registry.activeProfile.name)"))
                    if !self.showPage() { self.focusCommandBar(nil) }
                }
            }
        }
    }

    /// Clearing Browsing data cannot be undone, so the sheet names the Profile and asks for a range with nothing
    /// preselected. The Profile is the Active profile: the sheet blocks the window, so it cannot change underneath.
    private func askToClearBrowsingData(ofProfile id: ProfileID) {
        guard let window, clearSheet == nil, id == registry.activeProfileID else { return }
        let profile = registry.activeProfile
        let context = registry.active
        let sheet = ClearBrowsingDataSheet(
            profileName: profile.name,
            clear: { [weak self] range in
                guard let self else { return }
                endClearSheet()
                hideSuggestions()
                Task { @MainActor in
                    do {
                        try await context.clearBrowsingData(range)
                        self.announce(String(localized: "Cleared \(range.title) of “\(profile.name)”"))
                    } catch {
                        self.showClearingError(profileName: profile.name)
                    }
                }
            },
            cancel: { [weak self] in self?.endClearSheet() }
        )
        let hosting = NSWindow(contentViewController: NSHostingController(rootView: sheet))
        clearSheet = hosting
        window.beginSheet(hosting)
    }

    private func endClearSheet() {
        guard let sheet = clearSheet else { return }
        window?.endSheet(sheet)
        clearSheet = nil
    }

    private func showClearingError(profileName: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "The history of “\(profileName)” could not be cleared")
        alert.informativeText = String(localized: "Its website data was cleared. Try clearing the history again.")
        alert.beginSheetModal(for: window)
    }

    private func showDeletionError(_ error: any Error) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Some of the Profile’s website data could not be erased yet")
        alert.informativeText = String(localized: "Safira erases it the next time it opens.")
        alert.beginSheetModal(for: window)
    }

    /// Return or Escape in the Tab list. With no page to go to, a revealed sidebar that is hiding must not keep the
    /// keyboard focus, so the Command bar takes it.
    private func leaveSidebar() {
        let wasRevealed = presentation.isRevealed
        if !showPage(), wasRevealed { window?.makeFirstResponder(commandBar) }
    }

    // MARK: Compact mode

    private func applyReveal() {
        layout?.apply(presentation, animated: true)
        if presentation.isRevealed {
            announce(String(localized: "Sidebar shown"))
            focusTabList(nil)
        } else {
            announce(String(localized: "Sidebar hidden"))
            returnFocusToPage()
        }
    }

    /// The pointer touched the left edge.
    private func revealSidebarFromEdge() {
        guard presentation.isCompact, !presentation.isRevealed else { return }
        presentation.reveal()
        layout?.apply(presentation, animated: true)
        announce(String(localized: "Sidebar shown"))
    }

    private func hideSidebarAfterPointerLeft() {
        guard presentation.isRevealed else { return }
        presentation.hide()
        layout?.apply(presentation, animated: true)
        returnFocusToPage()
    }

    private func hideRevealedSidebar() {
        guard presentation.isRevealed else { return }
        presentation.hide()
        layout?.apply(presentation, animated: true)
    }

    /// A hidden sidebar cannot keep the keyboard focus.
    private func returnFocusToPage() {
        guard layout?.sidebarHasFocus == true else { return }
        if !showPage() { window?.makeFirstResponder(commandBar) }
    }

    private func announce(_ message: String) {
        guard let window else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    // MARK: Rendering

    private func observeSession() {
        withObservationTracking {
            render()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSession() }
        }
    }

    private func render() {
        let tab = session.selectedTab
        backButton.isEnabled = tab?.state.canGoBack == true
        forwardButton.isEnabled = tab?.state.canGoForward == true
        reloadButton.isEnabled = tab?.address != nil
        // While the Command bar is being edited its text is the user's, unless the shown Tab changed under it (another
        // Space or Tab shown by a shortcut): text typed for a ⌘T new Tab stays.
        let shownTabChanged = tab?.id != renderedTabID
        renderedTabID = tab?.id
        if commandBar.currentEditor() == nil || (shownTabChanged && session.commandBarTarget != .newTab) {
            commandBar.stringValue = tab?.address?.absoluteString ?? ""
        }
        window?.title = tab?.state.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Safira"
        pageArea.show(tab.flatMap { webContext.webView(for: $0.id) })
        updateSearchEngineSheet(query: session.searchAwaitingEngine)
        showPopups()
        showMatchBanner()
        updateDockIcon()
    }

    /// The Dock icon is the Active profile's Theme. Private windows leave it as it is.
    private func updateDockIcon() {
        let theme = ThemeCatalog.theme(id: registry.activeProfile.paletteID, fallback: ThemeCatalog.first)
        guard theme.id != dockIconThemeID else { return }
        dockIconThemeID = theme.id
        NSApp.applicationIconImage = DockIcon.image(for: theme)
    }

    /// The banner follows the Active profile's session. A new one is announced and goes by itself after a while; the
    /// session takes it down as soon as another Tab is shown.
    private func showMatchBanner() {
        let banner = session.matchBanner
        bannerModel.banner = banner
        bannerHost?.isHidden = banner == nil
        guard let banner, banner.id != announcedBannerID else { return }
        announcedBannerID = banner.id
        announce(String(localized: "This link was already open, so Safira showed that Tab. A button offers to open it in a new Tab."))
        let session = session
        Task { @MainActor [weak session] in
            try? await Task.sleep(for: .seconds(12))
            if session?.matchBanner?.id == banner.id { session?.dismissMatchBanner() }
        }
    }

    /// A popup shows in a floating panel while the Tab that opened it is the shown Tab of the Active profile, and is
    /// tucked away otherwise; its panel is made the first time it is wanted and goes when the popup ends.
    private func showPopups() {
        let shown = session.popups.filter { $0.openerTabID == session.selectedTabID }
        for popup in shown where popupPanels[popup.id] == nil {
            guard let webView = webContext.webView(forPopup: popup.id) else { continue }
            let session = session
            popupPanels[popup.id] = PopupPanelController(
                popup: popup, webView: webView,
                close: { [weak session] id in session?.closePopup(id) },
                onEnd: { [weak self] id in
                    self?.popupPanels[id] = nil
                    self?.showPage()
                })
        }
        for (id, panel) in popupPanels {
            panel.setVisible(shown.contains { $0.id == id }, over: window)
        }
    }

    private func updateSearchEngineSheet(query: String?) {
        guard let window else { return }
        switch (query, searchEngineSheet) {
        case (let query?, nil):
            // The engine goes to the Profile the search was typed in, even if another one is shown by then.
            let session = session
            let picker = SearchEnginePicker(
                query: query,
                choose: { [weak session] engine in session?.chooseSearchEngine(engine) },
                cancel: { [weak session] in session?.cancelSearchEngineChoice() }
            )
            let sheet = NSWindow(contentViewController: NSHostingController(rootView: picker))
            searchEngineSheet = sheet
            window.beginSheet(sheet)
        case (nil, let sheet?):
            window.endSheet(sheet)
            searchEngineSheet = nil
            if !showPage() {
                focusCommandBar(nil)
            }
        default:
            break
        }
    }

    // MARK: Layout

    private static let placeholder = String(localized: "Search or enter an address")
    private static let newTabPlaceholder = String(localized: "Search or enter an address to open in a new Tab")

    private func layOut(in window: NSWindow) {
        commandBar.placeholderString = Self.placeholder
        commandBar.setAccessibilityLabel("Command bar")
        commandBar.delegate = self
        commandBar.lineBreakMode = .byTruncatingTail
        commandBar.usesSingleLineMode = true

        let toolbar = NSStackView(views: [backButton, forwardButton, reloadButton, commandBar])
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        toolbar.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        commandBar.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let banner = NSHostingView(rootView: MatchBannerBar(
            model: bannerModel,
            openInNewTab: { [weak self] in
                guard let self else { return }
                session.openMatchBannerLinkInNewTab()
                showPage()
            },
            dismiss: { [weak self] in self?.session.dismissMatchBanner() }))
        banner.sizingOptions = [.intrinsicContentSize]
        banner.isHidden = true
        bannerHost = banner

        let content = NSStackView(views: [toolbar, banner, pageArea])
        content.orientation = .vertical
        content.spacing = 0
        content.alignment = .leading
        toolbar.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        banner.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        pageArea.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        let suggestions = CommandBarSuggestionHostingView(rootView: CommandBarSuggestionList(model: suggestionModel) {
            [weak self] in self?.openSuggestion($0)
        })
        suggestions.translatesAutoresizingMaskIntoConstraints = false
        suggestions.isHidden = true
        // Its width follows the Command bar's: the default min and max size constraints of a hosting view would cap
        // the field at the width of an empty list.
        suggestions.sizingOptions = [.intrinsicContentSize]
        suggestions.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        suggestions.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        content.addSubview(suggestions)
        NSLayoutConstraint.activate([
            suggestions.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -4),
            suggestions.leadingAnchor.constraint(equalTo: commandBar.leadingAnchor, constant: -8),
            suggestions.trailingAnchor.constraint(equalTo: commandBar.trailingAnchor, constant: 8),
        ])
        suggestionHost = suggestions

        let spaceActions = SpaceActions(
            edit: { [weak self] id in self?.editSpace(id) },
            delete: { [weak self] id in self?.confirmDeletion(of: id) }
        )
        let folderActions = FolderActions(
            create: { [weak self] parent in self?.editFolder(creatingIn: parent) },
            rename: { [weak self] id in self?.editFolder(creatingIn: nil, renaming: id) }
        )
        let profileActions = ProfileActions(
            select: { [weak self] id in self?.switchProfile { $0.selectProfile(id) } },
            edit: { [weak self] id in self?.editProfile(id) },
            delete: { [weak self] id in self?.confirmDeletion(ofProfile: id) },
            clearBrowsingData: { [weak self] id in self?.askToClearBrowsingData(ofProfile: id) }
        )
        let sidebar = NSHostingController(rootView: TabSidebar(registry: registry, profileActions: profileActions,
                                                               spaceActions: spaceActions,
                                                               folderActions: folderActions) { [weak self] in
            self?.leaveSidebar()
        })
        self.sidebar = sidebar
        let page = NSViewController()
        page.view = content
        let layout = SidebarLayoutViewController(sidebar: sidebar, page: page)
        layout.onPointerReachedLeftEdge = { [weak self] in self?.revealSidebarFromEdge() }
        layout.onPointerLeftSidebar = { [weak self] in self?.hideSidebarAfterPointerLeft() }
        self.layout = layout
        window.contentViewController = layout
        window.setContentSize(NSSize(width: 1200, height: 800))
    }

    /// SwiftUI draws a List with an AppKit table view; it is the view that takes the keyboard focus.
    private static func firstTableView(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        return view.subviews.lazy.compactMap { firstTableView(in: $0) }.first
    }

    private static func toolbarButton(symbol: String, label: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: action)
        button.bezelStyle = .toolbar
        button.toolTip = label
        return button
    }
}

/// Keeps the reserved browser-level shortcuts for the menu: a focused web page sees key equivalents before the menu
/// does and could otherwise swallow them. Which keys those are is decided by `KeyBindings.reservesKeyEquivalent`.
private final class MainWindow: NSWindow {
    var shortcuts: ShortcutController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if shortcuts?.bindings.reservesKeyEquivalent(KeyStroke(event)) == true,
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
