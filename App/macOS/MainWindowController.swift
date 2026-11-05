// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import AppKit
import ColorCore
import Commands
import DesignKit
import SafiraCore
import SafiraSession
import SafiraWeb
import SwiftUI

/// The Main window: AppKit owns the window, the Command bar field and the menu actions; SwiftUI draws the sidebar
/// column from ThemeKit's kit; the page canvas shows the selected Tab's web view, taken from the Profile's registry, or
/// SwiftUI content when there is no page. There is no bar above the page: the address and Back, Forward and Reload are
/// at the top of the column, and the Command bar floats over the page.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let registry: ProfileRegistry
    /// The Active profile's session: every Tab, Space and Command bar action reaches this Profile only.
    private var session: ProfileSession { registry.active.session }
    private var webContext: ProfileWebContext { registry.active.web }
    private let shortcuts: ShortcutController
    private let sideSetting: SidebarSideSetting
    private lazy var commandBar = FloatingCommandBar { [unowned self] in session }
    private let columnFocus = ColumnFocus()
    private var windowButtons: WindowButtonsReveal?
    private let pageArea = TabHostView()
    private var sidebar: NSViewController?
    private var layout: BrowserWindowLayout?
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
    private let bannerModel = MatchBannerModel()
    private var bannerHost: MatchBannerHostingView?
    private var announcedBannerID: UUID?

    init(registry: ProfileRegistry, shortcuts: ShortcutController, sideSetting: SidebarSideSetting) {
        self.registry = registry
        self.shortcuts = shortcuts
        self.sideSetting = sideSetting
        presentation = compactModeStore.load()
        let window = MainWindow(
            contentRect: NSRect(origin: .zero, size: SafiraDesign.mainWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Safira"
        window.shortcuts = shortcuts
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        // Safira rebuilds the Main window itself at launch; the system's window restoration would order a copy front.
        window.isRestorable = false
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
        commandBar.open(for: .newTab, text: "")
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

    /// Opens the floating Command bar on the shown Tab, its whole address selected: the way to see and change the
    /// address in Compact mode too.
    @objc func focusCommandBar(_ sender: Any?) {
        commandBar.open(for: .selectedTab, text: session.selectedTab?.address?.absoluteString ?? "")
    }

    /// At launch and after onboarding: the keyboard goes to the shown page, or to the Command bar when there is none,
    /// so a restored page is never covered by the panel.
    func showStartPage() {
        if !showPage() { focusCommandBar(nil) }
    }

    /// Moves the keyboard focus to the list of Tabs, where the arrow keys select a Tab. In Compact mode it shows the
    /// sidebar first.
    @objc func focusTabList(_ sender: Any?) {
        if presentation.isCompact, !presentation.isRevealed {
            presentation.reveal()
            layout?.apply(presentation, animated: true)
        }
        columnFocus.focusList()
    }

    /// ⌘1…⌘9: the menu item's tag is the Tab's place in the sidebar.
    @objc func showTabNumber(_ sender: Any?) {
        guard let number = (sender as? NSMenuItem)?.tag else { return }
        session.selectTab(number: number)
    }

    /// ⌃1…⌃9: the menu item's tag is the Space's place in the rail. The window's gradient moves to the Space's
    /// Theme with the kit's Theme change.
    @objc func showSpaceNumber(_ sender: Any?) {
        guard let number = (sender as? NSMenuItem)?.tag else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(MotionRole.themeChange.animation(reduceMotion: reduceMotion)) {
            session.selectSpace(number: number)
        }
    }

    /// The sidebar goes to the other side of every window; the choice is kept for the whole app.
    @objc func toggleSidebarSide(_ sender: Any?) {
        sideSetting.isRight.toggle()
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
            if presentation.isCompact { showPage() } else { focusTabList(nil) }
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
        let sheet = NSWindow.sheet(view)
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
        case #selector(showTabNumber(_:)): return menuItem.tag <= session.activeSpace.allTabs.count
        case #selector(showSpaceNumber(_:)): return menuItem.tag <= session.spaces.count
        case #selector(toggleSidebarSide(_:)):
            menuItem.state = sideSetting.isRight ? .on : .off
            return true
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
        commandBar.dismiss(returningFocus: false)
        render()
        announce(String(localized: "Profile: \(registry.activeProfile.name)"))
        showPage()
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
        let sheet = NSWindow.sheet(editor)
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
        let sheet = NSWindow.sheet(editor)
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
        commandBar.dismiss(returningFocus: false)
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
        let sheet = NSWindow.sheet(editor)
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
                commandBar.dismiss(returningFocus: false)
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
        let hosting = NSWindow.sheet(sheet)
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
    /// keyboard focus.
    private func leaveSidebar() {
        let wasRevealed = presentation.isRevealed
        if !showPage(), wasRevealed { window?.makeFirstResponder(nil) }
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

    /// The pointer touched the window's edge on the sidebar's side.
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
        if !showPage() { window?.makeFirstResponder(nil) }
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
        commandBar.follow(session)
        // While the Command bar is open on the shown Tab its text is the user's, unless the shown Tab changed under it
        // (another Space or Tab shown by a shortcut): text typed for a ⌘T new Tab stays.
        let shownTabChanged = tab?.id != renderedTabID
        renderedTabID = tab?.id
        if commandBar.isShown, shownTabChanged, session.commandBarTarget == .selectedTab {
            commandBar.field.stringValue = tab?.address?.absoluteString ?? ""
        }
        commandBar.appearance.theme = spaceTheme
        layout?.setSide(sideSetting.side)
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
            try? await Task.sleep(for: SafiraDesign.matchBannerLifetime)
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
            let sheet = NSWindow.sheet(picker)
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

    /// The active Space's Theme, or the Active profile's for a Space with none: the window's gradient and the column.
    private var spaceTheme: Theme {
        let profile = ThemeCatalog.theme(id: registry.activeProfile.paletteID, fallback: ThemeCatalog.first)
        return ThemeCatalog.theme(id: session.activeSpace.paletteID, fallback: profile)
    }

    private func layOut(in window: NSWindow) {
        // The content reaches the top edge under a transparent title bar; the title is still set, for the Window menu
        // and VoiceOver.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        commandBar.suggestions = { session, text in await session.suggestions(for: text) }
        commandBar.onClose = { [weak self] in
            self?.render()
            self?.showPage()
        }
        commandBar.onTabKey = { [weak self] in self?.focusTabList(nil) }
        commandBar.announce = { [weak self] in self?.announce($0) }

        let banner = MatchBannerHostingView(rootView: MatchBannerBar(
            model: bannerModel,
            theme: { [weak self] in self?.spaceTheme ?? ThemeCatalog.first },
            openInNewTab: { [weak self] in
                guard let self else { return }
                session.openMatchBannerLinkInNewTab()
                showPage()
            },
            dismiss: { [weak self] in self?.session.dismissMatchBanner() }))
        banner.isHidden = true
        bannerHost = banner
        let canvas = PageCanvasView(page: pageArea, banner: banner, commandBar: commandBar.overlay)

        let pageActions = PageActions(
            editAddress: { [weak self] in self?.focusCommandBar(nil) },
            newTab: { [weak self] in self?.newTab(nil) },
            showPage: { [weak self] in self?.leaveSidebar() })
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
        let sidebar = NSHostingController(rootView: TabSidebar(
            registry: registry, focus: columnFocus, pageActions: pageActions, profileActions: profileActions,
            spaceActions: spaceActions, folderActions: folderActions,
            side: sideSetting, shortcut: { [weak self] id in self?.shortcuts.bindings[id]?.display }))
        sidebar.sizingOptions = []
        // The column starts at the window's top edge: the title bar's buttons only show on demand.
        sidebar.safeAreaRegions = []
        self.sidebar = sidebar
        let theme: () -> Theme = { [weak self] in self?.spaceTheme ?? ThemeCatalog.first }
        let layout = BrowserWindowLayout(
            background: NSHostingView(rootView: WindowBackdrop(theme: theme)),
            overlayBackground: NSHostingView(rootView: WindowBackdrop(theme: theme)),
            column: sidebar, canvas: canvas, side: sideSetting.side)
        layout.onPointerReachedEdge = { [weak self] in self?.revealSidebarFromEdge() }
        layout.onPointerLeftSidebar = { [weak self] in self?.hideSidebarAfterPointerLeft() }
        self.layout = layout
        window.contentViewController = layout
        windowButtons = WindowButtonsReveal(window: window, layout: layout)
        window.setContentSize(SafiraDesign.mainWindowSize)
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
