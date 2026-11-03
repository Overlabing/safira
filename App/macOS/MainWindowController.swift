// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore
import SafiraSession
import SafiraWeb
import SwiftUI

/// The Main window: AppKit owns the window, the Command bar field and the menu actions; the page area shows the
/// selected Tab's web view, taken from the Profile's registry, or SwiftUI content when there is no page.
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
    private var searchEngineSheet: NSWindow?

    init(session: ProfileSession, webContext: ProfileWebContext) {
        self.session = session
        self.webContext = webContext
        let window = NSWindow(
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
        window.center()
        observeSession()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: Menu actions

    @objc func newTab(_ sender: Any?) {
        session.openNewTab()
        render()
        focusCommandBar(nil)
    }

    @objc func closeTab(_ sender: Any?) {
        session.closeSelectedTab()
        render()
        if session.selectedTab?.address == nil {
            focusCommandBar(nil)
        }
    }

    @objc func focusCommandBar(_ sender: Any?) {
        window?.makeFirstResponder(commandBar)
        commandBar.currentEditor()?.selectAll(nil)
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
        selectTab(offset: 1)
    }

    @objc func showPreviousTab(_ sender: Any?) {
        selectTab(offset: -1)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let tab = session.selectedTab
        switch menuItem.action {
        case #selector(closeTab(_:)): return tab != nil
        case #selector(goBack(_:)): return tab?.state.canGoBack == true
        case #selector(goForward(_:)): return tab?.state.canGoForward == true
        case #selector(reload(_:)): return tab?.address != nil
        case #selector(showNextTab(_:)), #selector(showPreviousTab(_:)): return session.tabs.count > 1
        default: return true
        }
    }

    // MARK: Command bar

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            session.submitCommandBar(commandBar.stringValue)
            render()
            if let tab = session.selectedTab, let webView = webContext.webView(for: tab.id) {
                window?.makeFirstResponder(webView)
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            commandBar.stringValue = session.selectedTab?.address?.absoluteString ?? ""
            commandBar.currentEditor()?.selectAll(nil)
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        render()
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
        if commandBar.currentEditor() == nil {
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
            if let tab = session.selectedTab, let webView = webContext.webView(for: tab.id) {
                window.makeFirstResponder(webView)
            } else {
                focusCommandBar(nil)
            }
        default:
            break
        }
    }

    private func selectTab(offset: Int) {
        let tabs = session.tabs
        guard let index = tabs.firstIndex(where: { $0.id == session.selectedTabID }), !tabs.isEmpty else { return }
        session.select(tabs[(index + offset + tabs.count) % tabs.count].id)
        render()
    }

    // MARK: Layout

    private func layOut(in window: NSWindow) {
        commandBar.placeholderString = "Search or enter an address"
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
        window.contentView = content
    }

    private static func toolbarButton(symbol: String, label: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: action)
        button.bezelStyle = .toolbar
        button.toolTip = label
        return button
    }
}
