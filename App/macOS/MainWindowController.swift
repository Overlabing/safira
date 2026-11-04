// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore
import SafiraSession
import SafiraWeb
import SwiftUI

/// The Main window: AppKit owns the window, the Command bar field and the menu actions; SwiftUI draws the sidebar of
/// Tabs; the page area shows the selected Tab's web view, taken from the Profile's registry, or SwiftUI content when
/// there is no page.
@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    private let session: ProfileSession
    private let webContext: ProfileWebContext
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
    private var renderedTabID: TabID?

    init(session: ProfileSession, webContext: ProfileWebContext) {
        self.session = session
        self.webContext = webContext
        presentation = compactModeStore.load()
        let window = MainWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Safira"
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
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
        webContext.webContentSettings.isFraudulentSiteWarningEnabled.toggle()
    }

    @objc func toggleAutoplayingSound(_ sender: Any?) {
        webContext.webContentSettings.isAutoplayingSoundAllowed.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let tab = session.selectedTab
        switch menuItem.action {
        case #selector(closeTab(_:)): return tab != nil
        case #selector(reopenClosedTab(_:)): return session.canReopenClosedTab
        case #selector(moveTabUp(_:)): return tab != nil && session.tabs.first?.id != tab?.id
        case #selector(moveTabDown(_:)): return tab != nil && session.tabs.last?.id != tab?.id
        case #selector(goBack(_:)): return tab?.state.canGoBack == true
        case #selector(goForward(_:)): return tab?.state.canGoForward == true
        case #selector(reload(_:)): return tab?.address != nil
        case #selector(showNextTab(_:)), #selector(showPreviousTab(_:)): return session.tabs.count > 1
        case #selector(deleteSpace(_:)): return session.canDeleteSpace
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
            menuItem.state = webContext.webContentSettings.isFraudulentSiteWarningEnabled ? .on : .off
            return true
        case #selector(toggleAutoplayingSound(_:)):
            menuItem.state = webContext.webContentSettings.isAutoplayingSoundAllowed ? .on : .off
            return true
        default: return true
        }
    }

    // MARK: Command bar

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            session.submitCommandBar(commandBar.stringValue)
            render()
            if session.commandBarTarget == nil {
                showPage()
            }
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            focusTabList(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
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

    func controlTextDidEndEditing(_ notification: Notification) {
        // Leaving the field abandons a pending new Tab, as Escape does.
        session.dismissCommandBar()
        commandBar.placeholderString = Self.placeholder
        render()
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
            title: space == nil ? String(localized: "New Space") : String(localized: "Rename Space"),
            confirmTitle: space == nil ? String(localized: "Create") : String(localized: "Rename"),
            name: space?.name ?? String(localized: "Space \(count + 1)"),
            emoji: space?.emoji ?? Self.newSpaceEmoji[count % Self.newSpaceEmoji.count],
            save: { [weak self] name, emoji in
                guard let self else { return }
                if let id {
                    session.renameSpace(id, name: name, emoji: emoji)
                } else {
                    session.createSpace(name: name, emoji: emoji)
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

    /// Deleting a Space closes its Tabs for good, so it is confirmed first. The last Space cannot be deleted.
    private func confirmDeletion(of id: SpaceID) {
        guard let window, session.canDeleteSpace, let space = session.spaces.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete the Space “\(space.name)”?")
        let tabs = space.tabs.isEmpty ? String(localized: "It has no Tab.")
            : String(AttributedString(localized: "Its ^[\(space.tabs.count) Tab](inflect: true) will close.").characters)
        alert.informativeText = tabs + " " + String(localized: "The Profile's logins and history are kept.")
        alert.addButton(withTitle: String(localized: "Delete Space")).hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.session.deleteSpace(id)
        }
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
    }

    private func updateSearchEngineSheet(query: String?) {
        guard let window else { return }
        switch (query, searchEngineSheet) {
        case (let query?, nil):
            let picker = SearchEnginePicker(
                query: query,
                choose: { [weak self] engine in self?.session.chooseSearchEngine(engine) },
                cancel: { [weak self] in self?.session.cancelSearchEngineChoice() }
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

        let content = NSStackView(views: [toolbar, pageArea])
        content.orientation = .vertical
        content.spacing = 0
        content.alignment = .leading
        toolbar.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
        pageArea.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        let spaceActions = SpaceActions(
            edit: { [weak self] id in self?.editSpace(id) },
            delete: { [weak self] id in self?.confirmDeletion(of: id) }
        )
        let sidebar = NSHostingController(rootView: TabSidebar(session: session, spaceActions: spaceActions) { [weak self] in
            self?.showPage()
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

/// Keeps the browser-level shortcuts for the menu: a focused web page sees key equivalents before the menu does and
/// could otherwise swallow them.
private final class MainWindow: NSWindow {
    private static let reserved: Set<String> = ["t", "n", "w", "T", "l", "q"]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command || modifiers == [.command, .shift],
           let key = event.charactersIgnoringModifiers, Self.reserved.contains(key),
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
