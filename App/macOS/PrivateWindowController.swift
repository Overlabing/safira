// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Commands
import SafiraCore
import SafiraSession
import SafiraWeb
import SwiftUI

/// A Private window: a separate window attached to one Profile, with no Spaces, no saved history and a data store that
/// is erased when it closes. It has no Profile switcher, no Space row and no Command bar suggestions: nothing it shows
/// comes from the Profile's history or Tabs. It answers the Tab commands of the menu the way the Main window does, and
/// the menu items it does not answer (Spaces, Profiles, Compact mode) are disabled while it is the key window.
@MainActor
final class PrivateWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate, NSMenuItemValidation {
    let context: PrivateContext
    /// Called once, when the window has closed and its data is being erased.
    var onClose: ((PrivateWindowController) -> Void)?
    private var session: ProfileSession { context.session }
    private let commandBar = NSTextField()
    private let backButton = PrivateWindowController.toolbarButton(symbol: "chevron.left", label: "Back",
                                                                  action: #selector(goBack(_:)))
    private let forwardButton = PrivateWindowController.toolbarButton(symbol: "chevron.right", label: "Forward",
                                                                     action: #selector(goForward(_:)))
    private let reloadButton = PrivateWindowController.toolbarButton(symbol: "arrow.clockwise", label: "Reload",
                                                                    action: #selector(reload(_:)))
    private let pageArea = TabHostView()
    private var sidebar: NSViewController?
    private var searchEngineSheet: NSWindow?
    private var popupPanels: [PopupID: PopupPanelController] = [:]
    private var renderedTabID: TabID?
    private var isClosed = false
    private let externalApps = WorkspaceExternalApps()
    private lazy var permissionPrompter = PermissionPrompter(
        window: { [weak self] in self?.window }, profileName: { _ in "" }, isPrivate: true)

    init(context: PrivateContext, shortcuts: ShortcutController) {
        self.context = context
        let window = PrivateWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.title(for: nil)
        window.shortcuts = shortcuts
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.setAccessibilityLabel(Self.title(for: nil))
        super.init(window: window)
        window.delegate = self
        context.web.permissionPrompt = { [unowned self] prompt in await permissionPrompter.ask(prompt) }
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
        announce(String(localized: "Private window. Nothing is saved. Attached to the Profile \(context.parent.name)."))
    }

    // MARK: Menu actions

    @objc func newTab(_ sender: Any?) {
        openCommandBar(for: .newTab, text: "", placeholder: Self.newTabPlaceholder)
    }

    @objc func closeTab(_ sender: Any?) {
        session.closeSelectedTab()
        render()
        if session.selectedTab?.address == nil { focusCommandBar(nil) }
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

    @objc func focusTabList(_ sender: Any?) {
        guard let list = sidebar.flatMap({ Self.firstTableView(in: $0.view) }) else { return }
        window?.makeFirstResponder(list)
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
        default: return true
        }
    }

    // MARK: Closing

    /// Closing the window ends the Private browsing: its pages close and its data store is emptied. The data store
    /// is non-persistent, so nothing was ever written for this to remove.
    func windowWillClose(_ notification: Notification) {
        guard !isClosed else { return }
        isClosed = true
        popupPanels.removeAll()
        let context = context
        Task { await context.close() }
        let onClose = onClose
        self.onClose = nil
        onClose?(self)
    }

    // MARK: Command bar

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            session.submitCommandBar(commandBar.stringValue)
            render()
            if session.commandBarTarget == nil { showPage() }
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            focusTabList(nil)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            session.dismissCommandBar()
            commandBar.placeholderString = Self.placeholder
            commandBar.stringValue = session.selectedTab?.address?.absoluteString ?? ""
            if !showPage() { commandBar.currentEditor()?.selectAll(nil) }
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        session.dismissCommandBar()
        commandBar.placeholderString = Self.placeholder
        render()
    }

    private func openCommandBar(for target: CommandBarTarget, text: String, placeholder: String) {
        commandBar.stringValue = text
        commandBar.placeholderString = placeholder
        window?.makeFirstResponder(commandBar)
        session.openCommandBar(for: target)
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
        backButton.isEnabled = tab?.state.canGoBack == true
        forwardButton.isEnabled = tab?.state.canGoForward == true
        reloadButton.isEnabled = tab?.address != nil
        let shownTabChanged = tab?.id != renderedTabID
        renderedTabID = tab?.id
        if commandBar.currentEditor() == nil || (shownTabChanged && session.commandBarTarget != .newTab) {
            commandBar.stringValue = tab?.address?.absoluteString ?? ""
        }
        let title = Self.title(for: tab?.state.title)
        window?.title = title
        window?.setAccessibilityLabel(title)
        pageArea.show(tab.flatMap { context.web.webView(for: $0.id) })
        updateSearchEngineSheet(query: session.searchAwaitingEngine)
        showPopups()
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
            let sheet = NSWindow(contentViewController: NSHostingController(rootView: picker))
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

    private static let placeholder = String(localized: "Search or enter an address")
    private static let newTabPlaceholder = String(localized: "Search or enter an address to open in a new Tab")

    /// The window title always says it is a Private window, which is also what VoiceOver reads when the window is key.
    private static func title(for page: String?) -> String {
        guard let page, !page.isEmpty else { return String(localized: "Private Window") }
        return String(localized: "Private Window – \(page)")
    }

    private func layOut(in window: NSWindow) {
        commandBar.placeholderString = Self.placeholder
        commandBar.setAccessibilityLabel("Command bar")
        commandBar.delegate = self
        commandBar.lineBreakMode = .byTruncatingTail
        commandBar.usesSingleLineMode = true

        let badge = NSTextField(labelWithString: String(localized: "Private"))
        badge.font = .systemFont(ofSize: 11, weight: .semibold)
        badge.textColor = .white
        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor(red: 0.20, green: 0.11, blue: 0.33, alpha: 1).cgColor
        badge.layer?.cornerRadius = 4
        badge.setAccessibilityElement(false)

        let toolbar = NSStackView(views: [backButton, forwardButton, reloadButton, badge, commandBar])
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

        let sidebar = NSHostingController(rootView: PrivateSidebar(session: session, parent: context.parent) {
            [weak self] in self?.showPage()
        })
        self.sidebar = sidebar
        let page = NSViewController()
        page.view = content
        window.contentViewController = SidebarLayoutViewController(sidebar: sidebar, page: page)
        window.setContentSize(NSSize(width: 1100, height: 760))
    }

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

/// Offers the reserved browser-level shortcuts to the menu before a focused page sees them, as the Main window does.
private final class PrivateWindow: NSWindow {
    var shortcuts: ShortcutController?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if shortcuts?.bindings.reservesKeyEquivalent(KeyStroke(event)) == true,
           NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
