// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import ColorCore
import ColorUI
import DesignKit
import Observation
import SafiraCore
import SafiraSession
import SwiftUI

// The pieces both windows build their sidebar column from, all of them ThemeKit kit views: the browser controls in
// the status line's place, Tab rows, the New Tab row, and the keyboard model of the list.

/// What the column's controls ask the window to do: the window owns the Command bar and the page's focus.
struct PageActions {
    /// Opens the Command bar on the shown Tab, its address selected.
    let editAddress: () -> Void
    /// Opens the Command bar for a new Tab.
    let newTab: () -> Void
    /// Return or Escape in the Tab list: the keyboard goes to the page.
    let showPage: () -> Void
}

/// The keyboard state of the Tab list. The window asks for the focus through it, since the list is a SwiftUI view
/// that AppKit cannot make first responder on its own.
@MainActor
@Observable
final class ColumnFocus {
    private(set) var request = 0
    var isListFocused = false

    func focusList() {
        request += 1
    }
}

/// The address of the shown Tab and Back, Forward and Reload, where Oisillon has its status line. The address is a
/// field pill showing the host; hovering shows the full address, VoiceOver reads it, and clicking opens the Command bar
/// with it selected.
struct BrowserControls: View {
    let session: ProfileSession
    let actions: PageActions
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let tab = session.selectedTab
        let address = tab?.address
        HStack(spacing: 0) {
            Button(action: actions.editAddress) {
                FieldPill(systemImage: symbol(for: address), title: address.map { AddressDisplay($0).host } ?? "",
                          placeholder: Self.placeholder)
            }
            .buttonStyle(PressedOpacityStyle())
            .help(address?.absoluteString ?? FloatingCommandBar.placeholder)
            // On the button itself, so that VoiceOver keeps its press action: the full address, not the host.
            .accessibilityLabel(Text("Address"))
            .accessibilityValue(Text(verbatim: address?.absoluteString ?? ""))
            .accessibilityHint(Text("Opens the Command bar"))
            HStack(spacing: 0) {
                IconButton(String(localized: "Back", comment: "Sidebar"), systemImage: "chevron.left") { session.goBack() }
                    .disabled(tab?.state.canGoBack != true)
                IconButton(String(localized: "Forward", comment: "Sidebar"), systemImage: "chevron.right") { session.goForward() }
                    .disabled(tab?.state.canGoForward != true)
                IconButton(String(localized: "Reload", comment: "Sidebar"), systemImage: "arrow.clockwise") { session.reload() }
                    .disabled(address == nil)
            }
            .padding(.trailing, tokens.spacing.listMargin - tokens.spacing.rowInsetHorizontal)
        }
        .frame(minHeight: tokens.size.statusLine)
        // The row sits near the window's top edge (`Spacing.columnTop`, set by the column's surface); its empty space
        // moves the window, as a title bar would.
        .background { Color.clear.contentShape(.rect).gesture(WindowDragGesture()) }
        .padding(.bottom, tokens.spacing.statusLineToList)
    }

    /// Shorter than the Command bar's own placeholder, which the help tag shows in full: the pill shares its row with
    /// three buttons and the French text did not fit.
    static let placeholder = String(localized: "Search or address",
                                    comment: "Sidebar: placeholder of the address pill with no page; keep it short")

    /// A lock for an encrypted page, a plain globe otherwise; a magnifying glass with no page.
    private func symbol(for address: URL?) -> String {
        guard let address else { return "magnifyingglass" }
        return address.scheme == "https" ? "lock.fill" : "globe"
    }
}

/// A Tab as a kit row: its initial on a tile, its title, and its host (or "Playing") under it; the close button while
/// the pointer is over it.
struct TabRowView: View {
    let tab: SafiraSession.Tab
    let isSelected: Bool
    let isListFocused: Bool
    let placement: RowPlacement
    let position: Int
    let count: Int
    let select: () -> Void
    let close: () -> Void
    @State private var isHovered = false
    @Environment(\.designTokens) private var tokens

    var body: some View {
        WithColorRoles { roles in
            ListRow(title, details: [subtitle], state: RowState(isSelected: isSelected, isHovered: isHovered,
                                                               isFocused: isSelected && isListFocused),
                    placement: placement) {
                Tile(.initial(initial))
            } trailing: {
                if isHovered {
                    Button(action: close) {
                        Image(systemName: "xmark").font(tokens.type.accessory.font)
                    }
                    .buttonStyle(PressedOpacityStyle())
                    .foregroundStyle(roles.secondaryText)
                    .help("Close Tab")
                    .accessibilityHidden(true)
                } else if tab.state.isPlayingMedia {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(tokens.type.accessory.font)
                        .foregroundStyle(roles.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .onHover { isHovered = $0 }
            .onTapGesture(perform: select)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityState)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, select)
            .accessibilityAction(named: "Close Tab", close)
        }
    }

    private var title: String {
        if let title = tab.state.title, !title.isEmpty { return title }
        return tab.address.map { AddressDisplay($0).host } ?? String(localized: "New Tab", comment: "Sidebar")
    }

    private var subtitle: String {
        if tab.state.isPlayingMedia { return String(localized: "Playing", comment: "Sidebar") }
        if tab.state.isLoading { return String(localized: "Loading", comment: "Sidebar") }
        return tab.address.map { AddressDisplay($0).host } ?? ""
    }

    private var initial: String {
        let source = tab.address?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? title
        return source.first.map { String($0).uppercased() } ?? "·"
    }

    /// The Tab's state then its place, as VoiceOver reads it after the title: "Loading, Playing media, 2 of 5".
    private var accessibilityState: String {
        var parts: [String] = []
        if tab.state.isLoading { parts.append(String(localized: "Loading", comment: "Sidebar")) }
        if tab.state.isPlayingMedia { parts.append(String(localized: "Playing media", comment: "Sidebar")) }
        if tab.isPinned { parts.append(String(localized: "Pinned", comment: "Sidebar")) }
        if let host = tab.address.map({ AddressDisplay($0).host }) { parts.append(host) }
        parts.append(String(localized: "\(position) of \(count)", comment: "Sidebar"))
        return parts.joined(separator: ", ")
    }
}

/// The row that opens the Command bar for a new Tab, with its shortcut.
struct NewTabRow: View {
    let shortcut: String?
    let newTab: () -> Void
    @State private var isHovered = false
    @Environment(\.designTokens) private var tokens

    var body: some View {
        WithColorRoles { roles in
            ListRow(String(localized: "New Tab", comment: "Sidebar"), state: RowState(isHovered: isHovered)) {
                Tile(.tintedSymbol("plus"))
            } trailing: {
                if let shortcut {
                    Text(verbatim: shortcut).role(tokens.type.count).foregroundStyle(roles.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .onHover { isHovered = $0 }
            .onTapGesture(perform: newTab)
            .accessibilityAction(.default, newTab)
        }
    }
}

/// The keyboard behaviour of a Tab list: arrows move the selection (which shows the Tab), Delete closes it, Return or
/// Escape goes to the page. The list draws its own focus ring around the selected row (`RowState.isFocused`).
struct TabListKeyboard: ViewModifier {
    let session: ProfileSession
    let focus: ColumnFocus
    let showPage: () -> Void
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused($isFocused)
            .onChange(of: focus.request) { isFocused = true }
            .onChange(of: isFocused) { focus.isListFocused = isFocused }
            .onKeyPress(.upArrow) {
                session.selectTab(offset: -1)
                return .handled
            }
            .onKeyPress(.downArrow) {
                session.selectTab(offset: 1)
                return .handled
            }
            .onKeyPress(.return) {
                showPage()
                return .handled
            }
            .onKeyPress(.escape) {
                showPage()
                return .handled
            }
            .onDeleteCommand { session.closeSelectedTab() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Tabs")
    }
}

/// A band of the Theme's colour holding a short text, in `ColorRoles.bandFill` and `bandText`: the Private window's
/// mark, naming the Profile it is attached to.
struct ThemeBand<Label: View>: View {
    let label: Label
    @Environment(\.designTokens) private var tokens

    init(@ViewBuilder label: () -> Label) {
        self.label = label()
    }

    var body: some View {
        WithColorRoles { roles in
            label
                .font(tokens.type.rowTitleEmphasized.font)
                .foregroundStyle(roles.bandText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, tokens.spacing.rowInsetHorizontal)
                .frame(minHeight: tokens.size.minTarget)
                .background(roles.bandFill, in: RoundedRectangle(cornerRadius: tokens.radius.row, style: .continuous))
        }
    }
}

/// The window background: ThemeKit's gradient in the Theme the window shows.
struct WindowBackdrop: View {
    let theme: () -> Theme

    var body: some View {
        WindowBackground()
            .theme(theme())
            .ignoresSafeArea()
    }
}
