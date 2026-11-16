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

// The pieces both windows build their sidebar column from, all of them ThemeKit kit views: the column's head (the
// navigation buttons and the address pill), Tab rows, the New Tab row, and the keyboard model of the list.

/// What the column's controls ask the window to do: the window owns the Command bar and the page's focus.
struct PageActions {
    /// Opens the Command bar on the shown Tab, its address selected.
    let editAddress: () -> Void
    /// Opens the Command bar for a new Tab.
    let newTab: () -> Void
    /// Return or Escape in the Tab list: the keyboard goes to the page.
    let showPage: () -> Void
    /// "Allow Prompts on This Site" in the cookie indicator: the site is excepted and the shown Tab reloads.
    let allowCookiePrompts: (String) -> Void
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

extension View {
    /// A browser window's column with ThemeKit's sidebar head, as in Zen
    /// (`sidebarColumn(sidebarButtonShortcut:titleBar:field:fieldAccessory:header:bottomBar:)`): on the line of the
    /// window's buttons, the kit's sidebar button then Back, Forward and Reload; under it the address pill the column's
    /// width, the shown Tab's host on its leading side and, with a page shown, the cookie indicator once Safira has
    /// handled the page's cookie prompt, `extensions` (the Main window's extension buttons; a Private window has none)
    /// and Copy Link inside it on its trailing edge. `sidebarShortcut` is the shortcut the sidebar button's help tag
    /// names.
    func browserColumn<Extensions: View, Header: View, BottomBar: View>(
        session: ProfileSession, actions: PageActions, sidebarShortcut: String?,
        @ViewBuilder extensions: () -> Extensions, @ViewBuilder header: () -> Header,
        @ViewBuilder bottomBar: () -> BottomBar
    ) -> some View {
        let extensions = extensions()
        return sidebarColumn(sidebarButtonShortcut: sidebarShortcut) {
            NavigationButtons(session: session)
        } field: {
            AddressField(session: session, editAddress: actions.editAddress)
        } fieldAccessory: {
            if let address = session.selectedTab?.address {
                if let cookiePrompt = session.selectedTab?.state.cookiePrompt, cookiePrompt.isShown {
                    CookiePromptIndicator(report: cookiePrompt, allow: actions.allowCookiePrompts)
                }
                extensions
                CopyLinkButton(address: address)
            }
        } header: {
            header()
        } bottomBar: {
            bottomBar()
        }
    }
}

/// Back, Forward and Reload, at the trailing end of the column's title bar row; disabled when they would do nothing.
private struct NavigationButtons: View {
    let session: ProfileSession

    var body: some View {
        let tab = session.selectedTab
        IconButton(String(localized: "Back", comment: "Sidebar"), systemImage: "arrow.left") { session.goBack() }
            .disabled(tab?.state.canGoBack != true)
        IconButton(String(localized: "Forward", comment: "Sidebar"), systemImage: "arrow.right") { session.goForward() }
            .disabled(tab?.state.canGoForward != true)
        IconButton(String(localized: "Reload", comment: "Sidebar"), systemImage: "arrow.clockwise") { session.reload() }
            .disabled(tab?.address == nil)
    }
}

/// The address in the pill: the shown Tab's host, larger, as in Zen, or the placeholder with no page; a not-secure mark
/// before it for a plain HTTP page (an encrypted page has none); the page zoom's badge when it is not 100%. Hovering
/// shows the full address and VoiceOver reads it; a click anywhere in the pill but on its buttons opens the Command
/// bar with it selected.
private struct AddressField: View {
    let session: ProfileSession
    let editAddress: () -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let address = session.selectedTab?.address
        let host = address.map { AddressDisplay($0).host }
        let isNotSecure = address.map { AddressDisplay($0).isNotSecure } ?? false
        Button(action: editAddress) {
            WithColorRoles { roles in
                HStack(spacing: tokens.spacing.pillTileToText) {
                    if isNotSecure {
                        Image(systemName: "lock.slash")
                            .font(tokens.type.accessory.font)
                            .foregroundStyle(roles.secondaryText)
                            .accessibilityHidden(true)
                    }
                    Text(host ?? Self.placeholder)
                        .role(tokens.type.sidebarFieldTitle)
                        .foregroundStyle(host == nil ? AnyShapeStyle(roles.secondaryText) : AnyShapeStyle(.primary))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let zoom {
                        Text(verbatim: zoom)
                            .role(tokens.type.count)
                            .monospacedDigit()
                            .foregroundStyle(roles.secondaryText)
                            .padding(.horizontal, tokens.spacing.rowGap)
                            .background(roles.secondaryText.opacity(0.15), in: Capsule(style: .continuous))
                            .fixedSize()
                            .help(String(localized: "Page zoom. Actual Size (⌘0) shows the page at its own size.", comment: "Sidebar: help tag of the zoom badge in the address field"))
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(LeadingGrown(by: tokens.spacing.sidebarFieldPillLeading))
            }
        }
        .buttonStyle(PressedOpacityStyle())
        .help(address?.absoluteString ?? FloatingCommandBar.placeholder)
        // On the button itself, so that VoiceOver keeps its press action: the full address, not the host.
        .accessibilityLabel(Text("Address"))
        .accessibilityValue(Text(verbatim: [
            isNotSecure ? String(localized: "Not Secure", comment: "Sidebar: VoiceOver value before the address of a plain HTTP page") : nil,
            address?.absoluteString,
            zoom.map { String(localized: "Zoom \($0)", comment: "Sidebar: VoiceOver value after the address; the page zoom, for example 125%") },
        ].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityHint(Text("Opens the Command bar"))
    }

    /// The page zoom when it is not 100%, as the badge shows it.
    private var zoom: String? {
        guard let tab = session.selectedTab, tab.address != nil, !tab.zoom.isActualSize else { return nil }
        return tab.zoom.percentage
    }

    static var placeholder: String {
        String(localized: "Search or address", comment: "Sidebar: placeholder of the address pill with no page; keep it short")
    }
}

/// The field's rectangle grown over the pill's leading inset, so a click there opens the Command bar too.
private struct LeadingGrown: Shape {
    let by: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX - by, y: rect.minY, width: rect.width + by, height: rect.height))
    }
}

/// Copies the shown page's full address (`AddressPasteboard`). For 1.5 s after the last click, its symbol is a check mark
/// and its help tag says the link was copied; VoiceOver hears it once, from the announcement, its label staying "Copy
/// Link".
private struct CopyLinkButton: View {
    let address: URL
    /// Clicks so far: each one restarts the confirmation's time.
    @State private var copies = 0
    @State private var copied = false

    var body: some View {
        let title = String(localized: "Copy Link", comment: "Sidebar: button in the address pill that copies the page's address")
        IconButton(copied ? String(localized: "Link Copied", comment: "Sidebar: help tag of the Copy Link button just after a click")
                          : title,
                   systemImage: copied ? "checkmark" : "link") { copy() }
            .accessibilityLabel(title)
            .task(id: copies) {
                guard copies > 0 else { return }
                try? await Task.sleep(for: Self.confirmation)
                guard !Task.isCancelled else { return }
                copied = false
            }
            .onChange(of: address) { copied = false }
    }

    private static let confirmation = Duration.seconds(1.5)

    private func copy() {
        AddressPasteboard.write(address, to: .general)
        copied = true
        copies += 1
        AccessibilityNotification.Announcement(String(localized: "Link copied", comment: "VoiceOver announcement after Copy Link")).post()
    }
}

/// Where a sidebar cell sits: on the column, or in an open Folder's panel, whose first and last cells round its corners.
enum SidebarCellPlacement: Equatable {
    case free
    case panel(level: Int, isFirst: Bool, isLast: Bool)
}

extension View {
    /// The kit's sidebar cell (`sidebarRowCell(state:placement:hoverID:)`) on the column. In a Folder's panel, the same
    /// cell with the panel drawn behind it a cell at a time, since a `List` cannot group cells under one `LayerPanel`.
    /// The cell tracks the pointer as the row `hoverID` of the column's `ListHover` and draws the hover fill from it,
    /// so `state` carries no hover and a hover step re-evaluates only the rows it enters and leaves.
    @ViewBuilder
    func sidebarCell(state: RowState, placement: SidebarCellPlacement, hoverID: AnyHashable) -> some View {
        switch placement {
        case .free:
            sidebarRowCell(state: state, placement: .free(firstInSection: false), hoverID: hoverID)
        case .panel(let level, let isFirst, let isLast):
            modifier(PanelCell(state: state, level: level, isFirst: isFirst, isLast: isLast, hoverID: hoverID))
        }
    }
}

/// A cell inside an open Folder's panel: the insets of the kit's sidebar cell for a `.layer` row, moved in by the
/// panel's own margin, and a slice of `LayerPanel`'s fill behind the row's background, rounded at the panel's ends.
private struct PanelCell: ViewModifier {
    let state: RowState
    let level: Int
    let isFirst: Bool
    let isLast: Bool
    let hoverID: AnyHashable
    @Environment(\.designTokens) private var tokens

    func body(content: Content) -> some View {
        let spacing = tokens.spacing
        let panelSide = spacing.listMargin - spacing.rowInsetHorizontal
        let panelEnd = spacing.layerInset - spacing.rowGap / 2
        let vertical = spacing.rowInsetVertical + spacing.textLines
        let side = panelSide + spacing.layerInset + spacing.rowInsetHorizontal
        let indent = CGFloat(max(level - 1, 0)) * spacing.layerIndent
        let radius = tokens.radius.layer
        let top = isFirst ? panelEnd : 0
        let bottom = isLast ? panelEnd : 0
        content
            .listHoverTracking(id: hoverID)
            .listRowInsets(EdgeInsets(top: spacing.rowGap / 2 + vertical + top, leading: side + indent,
                                      bottom: spacing.rowGap / 2 + vertical + bottom, trailing: side))
            .listRowSeparator(.hidden)
            .listRowBackground(
                ZStack {
                    UnevenRoundedRectangle(
                        topLeadingRadius: isFirst ? radius : 0, bottomLeadingRadius: isLast ? radius : 0,
                        bottomTrailingRadius: isLast ? radius : 0, topTrailingRadius: isFirst ? radius : 0,
                        style: .continuous)
                        .fill(Color.primary.opacity(tokens.emphasis.layer))
                        .accessibilityHidden(true)
                    ListRowBackground(state: state, placement: .layer(level: level), hoverID: hoverID)
                        .padding(.top, top)
                        .padding(.bottom, bottom)
                }
                .padding(.horizontal, panelSide))
    }
}

/// A sidebar row's content, with no padding of its own (the kit's sidebar cell carries it): a tile, the title in the
/// row's style (semibold when selected), detail lines in the secondary ink, a trailing accessory. A click anywhere on
/// the cell lands on the row, its insets included, not only on its tile and text.
struct SidebarRowContent<Leading: View, Trailing: View>: View {
    let title: String
    var details: [String] = []
    var isSelected = false
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @Environment(\.designTokens) private var tokens

    var body: some View {
        WithColorRoles { roles in
            HStack(alignment: details.isEmpty ? .center : .top, spacing: tokens.spacing.tileToText) {
                leading
                VStack(alignment: .leading, spacing: tokens.spacing.textLines) {
                    Text(title)
                        .role(isSelected ? tokens.type.rowTitleEmphasized : tokens.type.rowTitle)
                        .lineLimit(1)
                    ForEach(details, id: \.self) { line in
                        Text(line).role(tokens.type.rowDetail).foregroundStyle(roles.secondaryText).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                // Centred on the whole row, not on the title's line, when the row has detail lines.
                trailing.frame(maxHeight: .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(WholeCell(horizontal: tokens.spacing.listMargin,
                                    vertical: tokens.spacing.rowGap / 2 + tokens.spacing.rowInsetVertical
                                        + tokens.spacing.textLines))
        }
    }
}

/// The content's rectangle grown by the insets the kit's sidebar cell puts around it, so the row's whole background
/// takes the click.
private struct WholeCell: Shape {
    let horizontal: CGFloat
    let vertical: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: -horizontal, dy: -vertical))
    }
}

/// A site's icon on the kit's tile fill, or `fallback` (the site's initial, or a symbol) while no icon is cached for it.
/// Looking the icon up never fetches: only a loaded page does (`ProfileSiteIcons`).
struct SiteIconTile: View {
    let icons: ProfileSiteIcons?
    let address: URL?
    let fallback: TileContent
    var size: TileSize = .standard
    @Environment(\.designTokens) private var tokens

    var body: some View {
        if let icon = icons?.icon(for: address) {
            let side = tileSide * Self.iconShare
            Image(decorative: icon, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: side, height: side)
                .tileFill(size)
                .accessibilityHidden(true)
        } else {
            Tile(fallback, size: size)
        }
    }

    private var tileSide: CGFloat {
        switch size {
        case .standard: tokens.size.tile
        case .compact: tokens.size.compactTile
        case .small: tokens.size.smallTile
        case .status: tokens.size.statusTile
        }
    }

    /// The part of the tile the icon covers, the rest being the tile fill around it.
    private static let iconShare = 0.625

    /// The first letter of the site's host without `www.`, or of the title when there is no host; a dot for neither.
    static func initial(of address: URL?, title: String) -> String {
        let source = address?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? title
        return source.first.map { String($0).uppercased() } ?? "·"
    }
}

/// A Tab as a sidebar cell: its site's icon (or initial) on a tile, its title, and its host (or "Playing") under it;
/// the close button while the pointer is over it (`HoverAccessory`, so the row's own body never follows the pointer). A
/// dormant Tab shows the icon cached for its saved address.
struct TabRowView: View {
    let tab: SafiraSession.Tab
    let icons: ProfileSiteIcons
    let isSelected: Bool
    let isListFocused: Bool
    let placement: SidebarCellPlacement
    let position: Int
    let count: Int
    let select: () -> Void
    let close: () -> Void
    /// What a click on the icon does, when it does more than select the Tab: a Pinned tab goes back to its pinned address.
    var clickIcon: (() -> Void)?
    @Environment(\.designTokens) private var tokens

    var body: some View {
        WithColorRoles { roles in
            SidebarRowContent(title: title, details: [subtitle], isSelected: isSelected) {
                SiteIconTile(icons: icons, address: tab.address,
                             fallback: .initial(SiteIconTile.initial(of: tab.address, title: title)))
                    .overlay(alignment: .topTrailing) {
                        if tab.isAwayFromPinnedAddress { AwayFromPinnedAddressDot() }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(perform: clickIcon ?? select)
                    .help(tab.isAwayFromPinnedAddress ? String(localized: "Back to Pinned Address", comment: "Sidebar: tooltip of a Pinned tab's icon") : "")
            } trailing: {
                HoverAccessory(id: tab.id) {
                    Button(action: close) {
                        Image(systemName: "xmark").font(tokens.type.accessory.font)
                    }
                    .buttonStyle(PressedOpacityStyle())
                    .foregroundStyle(roles.secondaryText)
                    .help("Close Tab")
                    .accessibilityHidden(true)
                } idle: {
                    if tab.state.isPlayingMedia {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(tokens.type.accessory.font)
                            .foregroundStyle(roles.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
            }
            .onTapGesture(perform: select)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(accessibilityState)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, select)
            .accessibilityAction(named: "Close Tab", close)
            .modifier(BackToPinnedAddressAction(isAvailable: tab.isAwayFromPinnedAddress, perform: clickIcon))
        }
        .sidebarCell(state: RowState(isSelected: isSelected, isFocused: isSelected && isListFocused),
                     placement: placement, hoverID: tab.id)
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

    /// The Tab's state then its place, as VoiceOver reads it after the title: "Loading, Playing media, 2 of 5".
    private var accessibilityState: String {
        var parts: [String] = []
        if tab.state.isLoading { parts.append(String(localized: "Loading", comment: "Sidebar")) }
        if tab.state.isPlayingMedia { parts.append(String(localized: "Playing media", comment: "Sidebar")) }
        if tab.isPinned { parts.append(String(localized: "Pinned", comment: "Sidebar")) }
        if tab.isAwayFromPinnedAddress {
            parts.append(String(localized: "Away from its pinned address", comment: "Sidebar: VoiceOver state of a Pinned tab"))
        }
        if let host = tab.address.map({ AddressDisplay($0).host }) { parts.append(host) }
        parts.append(String(localized: "\(position) of \(count)", comment: "Sidebar"))
        return parts.joined(separator: ", ")
    }
}

/// The mark on a Pinned tab's icon while the Tab shows another page than the one it was pinned at: the kit's status
/// dot in the Theme's text colour, on the icon's top trailing corner.
private struct AwayFromPinnedAddressDot: View {
    @Environment(\.designTokens) private var tokens

    var body: some View {
        WithColorRoles { roles in
            Circle()
                .fill(roles.tintText)
                .frame(width: tokens.size.dot, height: tokens.size.dot)
                .offset(x: tokens.size.dot / 2, y: -tokens.size.dot / 2)
                .accessibilityHidden(true)
        }
    }
}

/// VoiceOver's "Back to Pinned Address" action on a Pinned tab away from its pinned address.
private struct BackToPinnedAddressAction: ViewModifier {
    let isAvailable: Bool
    let perform: (() -> Void)?

    func body(content: Content) -> some View {
        if isAvailable, let perform {
            content.accessibilityAction(named: Text("Back to Pinned Address", comment: "VoiceOver action of a Pinned tab"),
                                        perform)
        } else {
            content
        }
    }
}

/// The cell that opens the Command bar for a new Tab, with its shortcut. It shows as selected while the Command bar is
/// open for a new Tab.
struct NewTabRow: View {
    let shortcut: String?
    let isSelected: Bool
    let newTab: () -> Void
    @Environment(\.designTokens) private var tokens

    /// Its row in the column's `ListHover`, apart from every Tab's and Folder's.
    private static let hoverID = "safira.newTabRow"

    var body: some View {
        WithColorRoles { roles in
            Button(action: newTab) {
                SidebarRowContent(title: String(localized: "New Tab", comment: "Sidebar"), isSelected: isSelected) {
                    Tile(.tintedSymbol("plus"))
                } trailing: {
                    if let shortcut {
                        Text(verbatim: shortcut).role(tokens.type.count).foregroundStyle(roles.secondaryText)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(PressedOpacityStyle())
            .focusEffectDisabled()
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        }
        .sidebarCell(state: RowState(isSelected: isSelected), placement: .free, hoverID: Self.hoverID)
    }
}

/// A hairline between two groups of cells, on the column's margin, as a cell with no background.
struct SidebarSeparator: View {
    var body: some View {
        ColumnSeparator().listRowCell()
    }
}

/// The keyboard behaviour of a Tab list: arrows move the selection (which shows the Tab), Delete closes it, Return or
/// Escape goes to the page. The list draws its own focus ring around the selected row (`RowState.isFocused`): the
/// `List` keeps no selection of its own.
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
