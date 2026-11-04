// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Appearance
import ColorCore
import ColorUI
import DesignKit
import Observation
import SafiraCore
import SafiraSession
import SwiftUI

/// The Command bar as a floating glass panel centred over the page, with its suggestions under the field, in the look
/// of a ⌘K palette. It is shown exactly while the session has a target for it. The field is an AppKit text field, so
/// the window drives its focus (docs/architecture-v1.md §1.3); Return, Escape, a click outside the panel and leaving
/// the field close it.
@MainActor
final class FloatingCommandBar: NSObject, NSTextFieldDelegate {
    /// The session the Command bar acts on: the Active profile's, or the Private window's.
    var session: () -> ProfileSession
    /// Local suggestions; nil in a Private window, which reads nothing from the Profile.
    var suggestions: ((ProfileSession, String) async -> [CommandBarSuggestion])?
    /// The Command bar closed after opening something, or after Escape: the keyboard goes back to the page.
    var onClose: () -> Void = {}
    /// Tab or Shift-Tab: the keyboard goes to the Tab list.
    var onTabKey: () -> Void = {}
    var announce: (String) -> Void = { _ in }
    /// The Theme the panel's glass and inks follow.
    let appearance = CommandBarAppearance()

    let field = NSTextField()
    private(set) lazy var overlay = CommandBarOverlay(panel: CommandBarHostingView(rootView: CommandBarPanel(
        field: field, model: suggestionModel, appearance: appearance) { [weak self] in self?.open($0) }))
    private let suggestionModel = CommandBarSuggestionModel()
    private var suggestionTask: Task<Void, Never>?
    /// The text the shown suggestions were computed for: Return opens a highlighted one only while the text still is it.
    private var suggestionText: String?

    static let placeholder = String(localized: "Search or enter an address")
    static let newTabPlaceholder = String(localized: "Search or enter an address to open in a new Tab")

    init(session: @escaping () -> ProfileSession) {
        self.session = session
        super.init()
        field.placeholderString = Self.placeholder
        field.setAccessibilityLabel(String(localized: "Command bar"))
        field.delegate = self
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .preferredFont(forTextStyle: .title3)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        overlay.onOutsideClick = { [weak self] in self?.dismiss(returningFocus: false) }
    }

    var isShown: Bool { overlay.isShown }

    /// Shows the panel with `text` selected, for `target`. Setting the text or the focus ends an edit in progress,
    /// which would close the Command bar, so the session's target is set last.
    func open(for target: CommandBarTarget, text: String) {
        hideSuggestions()
        field.stringValue = text
        field.placeholderString = target == .newTab ? Self.newTabPlaceholder : Self.placeholder
        overlay.show()
        field.window?.makeFirstResponder(field)
        session().openCommandBar(for: target)
        field.currentEditor()?.selectAll(nil)
    }

    /// Closes the panel without opening anything: after ⌘T no Tab is created.
    func dismiss(returningFocus: Bool) {
        let wasShown = overlay.isShown
        hideSuggestions()
        overlay.hide()
        if session().isCommandBarOpen { session().dismissCommandBar() }
        if field.currentEditor() != nil { field.window?.makeFirstResponder(nil) }
        if wasShown, returningFocus { onClose() }
    }

    /// The session closed the Command bar on its own (another Profile shown, a search waiting for its engine).
    func follow(_ session: ProfileSession) {
        if !session.isCommandBarOpen, overlay.isShown { dismiss(returningFocus: false) }
    }

    // MARK: Field

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            if suggestionText == field.stringValue, let suggestion = suggestionModel.highlighted {
                open(suggestion)
                return true
            }
            let text = field.stringValue
            hideSuggestions()
            overlay.hide()
            session().submitCommandBar(text)
            field.window?.makeFirstResponder(nil)
            onClose()
            return true
        case #selector(NSResponder.moveDown(_:)):
            guard !suggestionModel.suggestions.isEmpty, suggestionText == field.stringValue else { return false }
            suggestionModel.moveDown()
            announceHighlight()
            return true
        case #selector(NSResponder.moveUp(_:)):
            guard !suggestionModel.suggestions.isEmpty, suggestionText == field.stringValue else { return false }
            suggestionModel.moveUp()
            announceHighlight()
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            dismiss(returningFocus: false)
            onTabKey()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(returningFocus: true)
            return true
        default:
            return false
        }
    }

    /// Typing asks the session for local suggestions: its open Tabs and its history. Nothing leaves the app, and no page
    /// loads until Return.
    func controlTextDidChange(_ notification: Notification) {
        updateSuggestions()
    }

    /// Leaving the field (a click in the sidebar) closes the Command bar, as Escape does.
    func controlTextDidEndEditing(_ notification: Notification) {
        guard overlay.isShown else { return }
        dismiss(returningFocus: false)
    }

    // MARK: Suggestions

    private func updateSuggestions() {
        suggestionTask?.cancel()
        let text = field.stringValue
        guard let suggestions, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hideSuggestions()
            return
        }
        // Results go to the session the text was typed for, and are dropped if another one is shown by the time they
        // arrive or the text moved on.
        let session = session()
        suggestionTask = Task { [weak self] in
            let found = await suggestions(session, text)
            guard let self, !Task.isCancelled, self.session() === session, field.stringValue == text,
                  field.currentEditor() != nil else { return }
            suggestionModel.show(found, typing: text)
            suggestionText = text
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
    }

    private func open(_ suggestion: CommandBarSuggestion) {
        hideSuggestions()
        overlay.hide()
        session().openSuggestion(suggestion)
        field.window?.makeFirstResponder(nil)
        onClose()
    }

    /// The keyboard stays in the text field, so VoiceOver is told which suggestion the arrows reached.
    private func announceHighlight() {
        announce(suggestionModel.highlighted?.title ?? field.stringValue)
    }
}

/// The Theme and appearance the panel is drawn in: the window's.
@MainActor
@Observable
final class CommandBarAppearance {
    var theme: Theme = SidebarComposition.privateTheme
}

/// Covers the page while the Command bar is open, and holds the panel in its upper third. A click outside the panel
/// closes it; one over the page is swallowed, so it never reaches the page behind, and one elsewhere in the window (the
/// sidebar) goes on to the control it landed on.
@MainActor
final class CommandBarOverlay: NSView {
    var onOutsideClick: (() -> Void)?
    private(set) var isShown = false
    private let panel: NSView
    private var panelTop: NSLayoutConstraint?
    private var clickMonitor: Any?

    init(panel: NSView) {
        self.panel = panel
        super.init(frame: .zero)
        isHidden = true
        setAccessibilityElement(false)
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        let top = panel.topAnchor.constraint(equalTo: topAnchor)
        panelTop = top
        NSLayoutConstraint.activate([
            top,
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -2 * SafiraDesign.commandBarSideMargin),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The panel's top stays put while suggestions come and go.
    override func layout() {
        panelTop?.constant = (bounds.height * SafiraDesign.commandBarTopFraction).rounded()
        super.layout()
    }

    /// Lets clicks through to the page outside the panel: the monitor decides what they do.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Shows the overlay and lays it out, so that the field inside can take the keyboard focus at once.
    func show() {
        guard !isShown else { return }
        isShown = true
        isHidden = false
        superview?.layoutSubtreeIfNeeded()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let windowNumber = event.windowNumber
            let location = event.locationInWindow
            // Delivered on the main thread, like every event of the application.
            let swallowed = MainActor.assumeIsolated { self?.swallows(windowNumber: windowNumber, at: location) ?? false }
            return swallowed ? nil : event
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        isHidden = true
        clickMonitor.map(NSEvent.removeMonitor)
        clickMonitor = nil
    }

    /// Closes the panel for a click outside it, and says whether the click must stop here (it was over the page).
    private func swallows(windowNumber: Int, at location: NSPoint) -> Bool {
        guard let window, windowNumber == window.windowNumber else { return false }
        let point = convert(location, from: nil)
        guard !panel.frame.contains(point) else { return false }
        // Hidden before anything else runs: the session's observation is asynchronous, and the click must not see the
        // panel still up.
        let overPage = bounds.contains(point)
        onOutsideClick?()
        return overPage
    }
}

/// The panel never takes the keyboard focus itself: clicking a suggestion leaves the field editing.
final class CommandBarHostingView: NSHostingView<CommandBarPanel> {
    override var acceptsFirstResponder: Bool { false }

    required init(rootView: CommandBarPanel) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

/// The glass panel: the field on top, the suggestions under a hairline. The glass sits on a veil of the window
/// background so its text stays legible over any page.
struct CommandBarPanel: View {
    let field: NSTextField
    let model: CommandBarSuggestionModel
    let appearance: CommandBarAppearance
    let choose: (CommandBarSuggestion) -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: SafiraDesign.commandBarRadius, style: .continuous)
        WithColorRoles { roles in
            VStack(spacing: 0) {
                HStack(spacing: tokens.spacing.tileToText) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(roles.secondaryText)
                        .accessibilityHidden(true)
                    FieldHost(field: field)
                }
                .padding(.horizontal, tokens.spacing.listMargin + tokens.spacing.rowInsetHorizontal)
                .frame(minHeight: tokens.size.floatingPill)
                if !model.suggestions.isEmpty {
                    ColumnSeparator()
                    CommandBarSuggestionList(model: model, choose: choose)
                }
            }
            .frame(width: SafiraDesign.commandBarWidth)
            .background(Color(nsColor: .windowBackgroundColor).opacity(SafiraDesign.commandBarVeil), in: shape)
            .surface(.glass(tint: 0), in: shape)
        }
        .theme(appearance.theme)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Command bar"))
    }
}

/// The window's text field, placed in the panel. The field belongs to the window controller, which drives its focus.
private struct FieldHost: NSViewRepresentable {
    let field: NSTextField

    func makeNSView(context: Context) -> NSTextField { field }

    func updateNSView(_ nsView: NSTextField, context: Context) {}
}
