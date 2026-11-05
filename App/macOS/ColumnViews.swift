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

/// The sidebar's head field, where Oisillon has its sidebar search (`sidebarColumn(field:…)` puts it there): the
/// address of the shown Tab, then Back, Forward and Reload. The address field shows the host; hovering shows the full
/// address, VoiceOver reads it, and clicking opens the Command bar with it selected.
struct BrowserControls: View {
    let session: ProfileSession
    let actions: PageActions
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let tab = session.selectedTab
        let address = tab?.address
        HStack(spacing: 0) {
            Button(action: actions.editAddress) {
                AddressField(symbol: symbol(for: address), host: address.map { AddressDisplay($0).host } ?? "",
                             placeholder: Self.placeholder)
            }
            .buttonStyle(PressedOpacityStyle())
            .help(address?.absoluteString ?? FloatingCommandBar.placeholder)
            // On the button itself, so that VoiceOver keeps its press action: the full address, not the host.
            .accessibilityLabel(Text("Address"))
            .accessibilityValue(Text(verbatim: address?.absoluteString ?? ""))
            .accessibilityHint(Text("Opens the Command bar"))
            IconButton(String(localized: "Back", comment: "Sidebar"), systemImage: "chevron.left") { session.goBack() }
                .disabled(tab?.state.canGoBack != true)
            IconButton(String(localized: "Forward", comment: "Sidebar"), systemImage: "chevron.right") { session.goForward() }
                .disabled(tab?.state.canGoForward != true)
            IconButton(String(localized: "Reload", comment: "Sidebar"), systemImage: "arrow.clockwise") { session.reload() }
                .disabled(address == nil)
        }
    }

    /// Shorter than the Command bar's own placeholder, which the help tag shows in full: the field shares its row with
    /// three buttons and the French text did not fit.
    static let placeholder = String(localized: "Search or address",
                                    comment: "Sidebar: placeholder of the address pill with no page; keep it short")

    /// A lock for an encrypted page, a plain globe otherwise; a magnifying glass with no page.
    private func symbol(for address: URL?) -> String {
        guard let address else { return "magnifyingglass" }
        return address.scheme == "https" ? "lock.fill" : "globe"
    }
}

/// The address as a sidebar search field draws its text: a capsule `Size.sidebarField` tall on glass, a symbol in the
/// secondary ink, the host in the label colour or the placeholder in the secondary ink.
private struct AddressField: View {
    let symbol: String
    let host: String
    let placeholder: String
    @Environment(\.designTokens) private var tokens

    var body: some View {
        WithColorRoles { roles in
            HStack(spacing: tokens.spacing.pillTileToText) {
                Image(systemName: symbol)
                    .font(tokens.type.accessory.font)
                    .foregroundStyle(roles.secondaryText)
                    .accessibilityHidden(true)
                Text(host.isEmpty ? placeholder : host)
                    .role(tokens.type.rowTitle)
                    .foregroundStyle(host.isEmpty ? AnyShapeStyle(roles.secondaryText) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, tokens.spacing.rowInsetHorizontal)
            .frame(height: tokens.size.sidebarField)
            .surface(.glass(tint: 0), in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
        }
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
/// row's style (semibold when selected), detail lines in the secondary ink, a trailing accessory.
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
                trailing
            }
            .contentShape(.rect)
        }
    }
}

/// A site's icon on the kit's tile fill, or the site's initial on the kit's letter tile while no icon is cached for it.
/// Looking the icon up never fetches: only a loaded page does (`ProfileSiteIcons`).
struct SiteIconTile: View {
    let icons: ProfileSiteIcons?
    let address: URL?
    let initial: String
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
            Tile(.initial(initial), size: size)
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
    @Environment(\.designTokens) private var tokens

    var body: some View {
        WithColorRoles { roles in
            SidebarRowContent(title: title, details: [subtitle], isSelected: isSelected) {
                SiteIconTile(icons: icons, address: tab.address,
                             initial: SiteIconTile.initial(of: tab.address, title: title))
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
        if let host = tab.address.map({ AddressDisplay($0).host }) { parts.append(host) }
        parts.append(String(localized: "\(position) of \(count)", comment: "Sidebar"))
        return parts.joined(separator: ", ")
    }
}

/// The cell that opens the Command bar for a new Tab, with its shortcut.
struct NewTabRow: View {
    let shortcut: String?
    let newTab: () -> Void
    @Environment(\.designTokens) private var tokens

    /// Its row in the column's `ListHover`, apart from every Tab's and Folder's.
    private static let hoverID = "safira.newTabRow"

    var body: some View {
        WithColorRoles { roles in
            SidebarRowContent(title: String(localized: "New Tab", comment: "Sidebar")) {
                Tile(.tintedSymbol("plus"))
            } trailing: {
                if let shortcut {
                    Text(verbatim: shortcut).role(tokens.type.count).foregroundStyle(roles.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            .onTapGesture(perform: newTab)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, newTab)
        }
        .sidebarCell(state: RowState(), placement: .free, hoverID: Self.hoverID)
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
