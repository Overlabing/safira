// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import AppKit
import ColorCore
import CommandKit
import CommandKitAppKit
import Commands
import SafiraCore
import SafiraSession
import SafiraSettings
import SafiraWeb
import SwiftUI

/// A Private window: a separate window attached to one Profile, with no Spaces, no saved history and a data store that
/// is erased when it closes. It has the Main window's layout (address and Back, Forward and Reload at the top of the
/// column, the Command bar floating over the page, no bar above it), always dark and in its own purple Theme. It has no
/// Profile switcher, no Space switcher and no Command bar suggestions: nothing it shows comes from the Profile's
/// history or Tabs. It answers the Tab commands of the menu the way the Main window does, and the menu items it does not
/// answer (Spaces, Profiles, Compact mode) are disabled while it is the key window.
@MainActor
final class PrivateWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let context: PrivateContext
    /// Called once, when the window has closed and its data is being erased.
    var onClose: ((PrivateWindowController) -> Void)?
    private var session: ProfileSession { context.session }
    private lazy var commandBar = FloatingCommandBar { [unowned self] in session }
    private let columnFocus = ColumnFocus()
    private let findBarFocus = FindBarFocus()
    private var findBarHost: NSView?
    private let pageArea = TabHostView.withEmptyPage()
    private let crashedPage = CrashedPageHost()
    private var layout: BrowserWindowLayout?
    private var toolbar: SidebarToolbar?
    /// The sidebar button hides and shows this window's column; a Private window has no Compact mode and keeps nothing.
    private var presentation = SidebarPresentation()
    private var searchEngineSheet: NSWindow?
    private var popupPanels: [PopupID: PopupPanelController] = [:]
    private var renderedTabID: TabID?
    private var isClosed = false
    private let externalApps = WorkspaceExternalApps()
    private lazy var permissionPrompter = PermissionPrompter(
        window: { [weak self] in self?.window }, profileName: { _ in "" }, isPrivate: true)
    private var canvas: PageCanvasView?
    /// The Library in this window: Downloads, Extensions and Safira's settings only, since the Profile's are not this
    /// window's to change.
    private lazy var settings = LibraryHost(
        isPrivate: true,
        downloads: LibraryDownloads(downloads: { [unowned self] in context.web.downloads }, web: { [unowned self] in context.web }),
        theme: { SidebarComposition.privateTheme },
        pageTitle: { [weak self] in self?.session.selectedTab?.state.title })

    init(context: PrivateContext, shortcuts: ShortcutController) {
        self.context = context
        let window = PrivateWindow(
            contentRect: NSRect(origin: .zero, size: SafiraDesign.privateWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = Self.title(for: nil)
        window.shortcuts = shortcuts
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        // A Private window keeps nothing: it never comes back after a relaunch.
        window.isRestorable = false
        window.setAccessibilityLabel(Self.title(for: nil))
        super.init(window: window)
        window.delegate = self
        context.web.permissionPrompt = { [unowned self] prompt in await permissionPrompter.ask(prompt) }
        context.web.pagePanels = permissionPrompter.pagePanels
        context.session.appLinks.handlers = AppLinkHandlers(
            launcher: externalApps,
            prompt: { [unowned self] prompt in await permissionPrompter.confirmOpen(prompt) },
            refusal: { [unowned self] refusal in await permissionPrompter.refuseOpen(refusal) },
            openFailure: { [unowned self] app, _ in await permissionPrompter.reportOpenFailure(of: app) })
        layOut(in: window)
        window.center()
        observeSession()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Shows the window with the keyboard in the Command bar, and tells VoiceOver what kind of window it is.
    func open(cascadedFrom origin: NSPoint?) {
        if let origin { window?.setFrameTopLeftPoint(origin) }
        showWindow(nil)
        focusCommandBar(nil)
        announce(String(localized: "Private window. Nothing is saved. Attached to the Profile \(context.parent.name).", comment: "Private window"))
    }

    // MARK: Library

    func attachSettings(_ content: SettingsContent) {
        guard let canvas, let layout else { return }
        settings.didShow = { [weak self] in self?.libraryDidShow() }
        settings.didHide = { [weak self] in self?.libraryDidHide() }
        settings.attach(content, to: layout, canvas: canvas)
        (window as? PrivateWindow)?.libraryBack = { [weak self] in self?.settings.isPresented == true }
        (window as? PrivateWindow)?.closeLibrary = { [weak self] in self?.settings.close() }
    }

    @objc func openSettings(_ sender: Any?) {
        settings.open(from: sender)
    }

    override func cancelOperation(_ sender: Any?) {
        if settings.isPresented { settings.close() }
    }

    private func leaveSettings() {
        if settings.isPresented { settings.close() }
    }

    private func libraryDidShow() {
        if commandBar.isShown { commandBar.dismiss(returningFocus: false) }
        closeFindBar()
    }

    private func libraryDidHide() {
        if !showPage() { focusCommandBar(nil) }
    }

    // MARK: Menu actions

    /// ⌥⌘L: the Library on this window's downloads; again, it closes.
    @objc func showDownloads(_ sender: Any?) {
        settings.toggle(.item(.downloads))
    }

    @objc func newTab(_ sender: Any?) {
        leaveSettings()
        commandBar.open(for: .newTab, text: "")
    }

    @objc func closeTab(_ sender: Any?) {
        if settings.isPresented {
            settings.close()
            return
        }
        session.closeSelectedTab()
        render()
        if session.selectedTab?.address == nil { focusCommandBar(nil) }
    }

    @objc func reopenClosedTab(_ sender: Any?) {
        session.reopenClosedTab()
        render()
    }

    @objc func focusCommandBar(_ sender: Any?) {
        leaveSettings()
        commandBar.open(for: .selectedTab, text: session.selectedTab?.address?.absoluteString ?? "")
    }

    @objc func focusTabList(_ sender: Any?) {
        leaveSettings()
        columnFocus.focusList()
    }

    @objc func showTabNumber(_ sender: Any?) {
        guard let number = (sender as? NSMenuItem)?.tag else { return }
        leaveSettings()
        session.selectTab(number: number)
    }

    @objc func moveTabUp(_ sender: Any?) {
        session.selectedTabID.map { session.move($0, by: -1) }
    }

    @objc func moveTabDown(_ sender: Any?) {
        session.selectedTabID.map { session.move($0, by: 1) }
    }

    @objc func goBack(_ sender: Any?) {
        if settings.isPresented {
            settings.close()
            return
        }
        session.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        session.goForward()
    }

    @objc func reload(_ sender: Any?) {
        session.reload()
    }

    @objc func showNextTab(_ sender: Any?) {
        leaveSettings()
        session.selectTab(offset: 1)
    }

    @objc func showPreviousTab(_ sender: Any?) {
        leaveSettings()
        session.selectTab(offset: -1)
    }

    // MARK: Page

    /// ⌘F: the find bar over the page, its field focused with its text selected.
    @objc func findInPage(_ sender: Any?) {
        leaveSettings()
        Task { await session.find.show() }
        findBarFocus.focusField()
    }

    @objc func findNext(_ sender: Any?) {
        Task { await session.find.next() }
    }

    @objc func findPrevious(_ sender: Any?) {
        Task { await session.find.previous() }
    }

    private func closeFindBar() {
        let responder = window?.firstResponder as? NSView
        let hadFocus = findBarHost.map { responder?.isDescendant(of: $0) == true } ?? false
        session.find.close()
        if hadFocus { showPage() }
    }

    @objc func zoomIn(_ sender: Any?) {
        session.zoomIn()
    }

    @objc func zoomOut(_ sender: Any?) {
        session.zoomOut()
    }

    @objc func actualSize(_ sender: Any?) {
        session.resetZoom()
    }

    @objc func printPage(_ sender: Any?) {
        guard let window, let tab = session.selectedTab, let webView = context.web.webView(for: tab.id) else { return }
        PagePrinter.print(webView, in: window)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let tab = session.selectedTab
        switch menuItem.action {
        case #selector(closeTab(_:)): return tab != nil
        case #selector(reopenClosedTab(_:)): return session.canReopenClosedTab
        case #selector(moveTabUp(_:)): return tab != nil && session.tabs.first?.id != tab?.id
        case #selector(moveTabDown(_:)): return tab != nil && session.tabs.last?.id != tab?.id
        case #selector(goBack(_:)): return settings.isPresented || tab?.state.canGoBack == true
        case #selector(goForward(_:)): return tab?.state.canGoForward == true
        case #selector(reload(_:)): return tab?.address != nil
        case #selector(findInPage(_:)), #selector(printPage(_:)): return tab?.address != nil
        case #selector(findNext(_:)), #selector(findPrevious(_:)): return tab?.address != nil && !session.find.text.isEmpty
        case #selector(zoomIn(_:)): return session.canZoomIn
        case #selector(zoomOut(_:)): return session.canZoomOut
        case #selector(actualSize(_:)): return session.canResetZoom
        case #selector(showNextTab(_:)), #selector(showPreviousTab(_:)): return session.tabs.count > 1
        case #selector(showTabNumber(_:)): return menuItem.tag <= session.tabs.count
        default: return true
        }
    }

    // MARK: Closing

    /// Closing the window ends the Private browsing: its pages close and its data store is emptied. The data store
    /// is non-persistent, so nothing was ever written for this to remove.
    func windowWillClose(_ notification: Notification) {
        guard !isClosed else { return }
        isClosed = true
        commandBar.dismiss(returningFocus: false)
        popupPanels.removeAll()
        let context = context
        Task { await context.close() }
        let onClose = onClose
        self.onClose = nil
        onClose?(self)
    }

    @discardableResult
    private func showPage() -> Bool {
        guard let tab = session.selectedTab, let webView = context.web.webView(for: tab.id) else { return false }
        return window?.makeFirstResponder(webView) ?? false
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
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                self.observeSession()
            }
        }
    }

    private func render() {
        let tab = session.selectedTab
        commandBar.follow(session)
        let shownTabChanged = tab?.id != renderedTabID
        renderedTabID = tab?.id
        if shownTabChanged { closeFindBar() }
        if commandBar.isShown, shownTabChanged, session.commandBarTarget == .selectedTab {
            commandBar.field.stringValue = tab?.address?.absoluteString ?? ""
        }
        let title = Self.title(for: tab?.state.title)
        window?.title = title
        window?.setAccessibilityLabel(title)
        if let tab, tab.crash == .crashed {
            pageArea.show(crashedPage.view(site: tab.address?.host) { [weak self] in self?.session.reload() })
        } else {
            pageArea.show(tab.flatMap { context.web.webView(for: $0.id) })
        }
        session.selectedTabIsShown()
        updateSearchEngineSheet(query: session.searchAwaitingEngine)
        showPopups()
    }

    private func toggleColumn() {
        presentation.toggleCompact()
        layout?.apply(presentation, animated: true)
    }

    func window(_ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions)
        -> NSApplication.PresentationOptions {
        SidebarFullScreen.options(proposedOptions)
    }

    private func showPopups() {
        let shown = session.popups.filter { $0.openerTabID == session.selectedTabID }
        for popup in shown where popupPanels[popup.id] == nil {
            guard let webView = context.web.webView(forPopup: popup.id) else { continue }
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

    /// The engine chosen here stays in this window: a Private window never writes to its Profile.
    private func updateSearchEngineSheet(query: String?) {
        guard let window else { return }
        switch (query, searchEngineSheet) {
        case (let query?, nil):
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
            if !showPage() { focusCommandBar(nil) }
        default:
            break
        }
    }

    // MARK: Layout

    /// The window title always says it is a Private window, which is also what VoiceOver reads when the window is key.
    private static func title(for page: String?) -> String {
        guard let page, !page.isEmpty else { return String(localized: "Private Window", comment: "Private window") }
        return String(localized: "Private Window – \(page)", comment: "Private window")
    }

    private func layOut(in window: NSWindow) {
        // Always dark, in the Private Theme's purple: what tells a Private window from the Main window at a glance.
        window.appearance = NSAppearance(named: .darkAqua)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        commandBar.appearance.theme = SidebarComposition.privateTheme
        commandBar.onClose = { [weak self] in
            self?.render()
            self?.showPage()
        }
        commandBar.onTabKey = { [weak self] in self?.focusTabList(nil) }
        commandBar.announce = { [weak self] in self?.announce($0) }
        let findBar = FindBarHostingView(rootView: FindBar(
            find: { [unowned self] in session.find },
            focus: findBarFocus, theme: { SidebarComposition.privateTheme },
            close: { [weak self] in self?.closeFindBar() }))
        findBarHost = findBar
        let canvas = PageCanvasView(page: pageArea, banner: NSView(), findBar: findBar, commandBar: commandBar.overlay)
        self.canvas = canvas
        let pageActions = PageActions(
            editAddress: { [weak self] in self?.focusCommandBar(nil) },
            // As in the Main window: the Command bar opens once the click on the New Tab row is over.
            newTab: { Task { @MainActor [weak self] in self?.newTab(nil) } },
            showPage: { [weak self] in self?.showPage() },
            allowCookiePrompts: { [weak self] site in self?.context.allowCookiePrompts(onSite: site) })
        let column = PrivateSidebar(session: session, parent: context.parent, focus: columnFocus, pageActions: pageActions,
                                    web: context.web, library: { [weak self] in self?.settings.open($0) })
        let theme: () -> Theme = { SidebarComposition.privateTheme }
        let layout = BrowserWindowLayout(background: NSHostingView(rootView: WindowBackdrop(theme: theme)),
                                         column: column, canvas: canvas)
        layout.onToggleSidebar = { [weak self] in self?.toggleColumn() }
        self.layout = layout
        window.contentViewController = layout
        let toolbar = SidebarToolbar(items: layout.toolbarItems)
        toolbar.install(in: window)
        self.toolbar = toolbar
        window.setContentSize(SafiraDesign.privateWindowSize)
    }
}

/// Offers the reserved browser-level shortcuts to the menu before a focused page sees them, as the Main window does.
private final class PrivateWindow: NSWindow {
    var shortcuts: ShortcutController?
    var libraryBack: (() -> Bool)?
    var closeLibrary: (@MainActor () -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if libraryBack?() == true, let closeLibrary, LibraryBackGesture.handle(event, back: closeLibrary) { return }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let shortcut = Shortcut(event: event), shortcuts?.takesKeyBeforeFocusedView(shortcut) == true,
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
