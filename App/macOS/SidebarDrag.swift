// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DesignKit
import SafiraCore
import SafiraSession
import SwiftUI
import UniformTypeIdentifiers

/// A drag inside one sidebar: the Tab or Folder it carries, and the place it would land now. Only a drag that started on
/// one of the sidebar's own rows has an item, so text or links dragged in from another app find no place and are
/// refused.
@MainActor
@Observable
final class SidebarDrag {
    /// The place under the pointer, the row that proposed it, and the Folder it enters when the pointer is on a Folder's
    /// middle (that Folder is highlighted instead of a line being drawn).
    struct Hover: Equatable {
        var place: SidebarDropPlace
        var into: FolderID?
        var row: AnyHashable
    }

    private(set) var item: PinnedItemID?
    private(set) var hover: Hover?

    var isDragging: Bool { item != nil }

    /// The line's place, when one is drawn.
    var linePlace: SidebarDropPlace? {
        guard let hover, hover.into == nil else { return nil }
        return hover.place
    }

    func begin(_ item: PinnedItemID) -> NSItemProvider {
        self.item = item
        hover = nil
        return NSItemProvider(object: PinnedDrag.text(for: item) as NSString)
    }

    func end() {
        item = nil
        hover = nil
    }

    func propose(_ hover: Hover?) {
        if self.hover != hover { self.hover = hover }
    }

    /// The pointer left a row: its proposal goes, unless another row has already made one.
    func leave(_ row: AnyHashable) {
        if hover?.row == row { hover = nil }
    }
}

/// What a drag carries between the sidebar's rows, as plain text.
enum PinnedDrag {
    static func text(for item: PinnedItemID) -> String {
        switch item {
        case .tab(let id): "safira-tab:\(id.rawValue.uuidString)"
        case .folder(let id): "safira-folder:\(id.rawValue.uuidString)"
        }
    }
}

/// How a row turns the pointer's height on it into a place: a row's upper half is the gap above it, its lower half the
/// gap below; a Folder keeps its middle for "into it" and its quarters for the gaps; a gap (the insertion line, the
/// New Tab row, the empty pinned area) is one place whatever the height.
enum SidebarDropZone {
    case row(above: SidebarDropPlace, below: SidebarDropPlace)
    case folder(FolderID, above: SidebarDropPlace, into: SidebarDropPlace, below: SidebarDropPlace)
    case gap(SidebarDropPlace)

    func hover(at y: CGFloat, height: CGFloat, row: AnyHashable) -> SidebarDrag.Hover {
        switch self {
        case .row(let above, let below):
            SidebarDrag.Hover(place: y < height / 2 ? above : below, row: row)
        case .folder(let folder, let above, let into, let below):
            if y < height / 4 {
                SidebarDrag.Hover(place: above, row: row)
            } else if y > height * 3 / 4 {
                SidebarDrag.Hover(place: below, row: row)
            } else {
                SidebarDrag.Hover(place: into, into: folder, row: row)
            }
        case .gap(let place):
            SidebarDrag.Hover(place: place, row: row)
        }
    }
}

extension View {
    /// Makes a sidebar row draggable, carrying `item` (a Tab or a Folder). A click still reaches the row's own tap.
    func sidebarDragSource(_ item: PinnedItemID, drag: SidebarDrag) -> some View {
        onDrag { drag.begin(item) }
            .onDragSessionUpdated { session in
                switch session.phase {
                case .ended, .dataTransferCompleted: drag.end()
                default: break
                }
            }
    }

    /// Makes a sidebar row a place to drop what `drag` carries, as `zone` says, into `session`.
    func sidebarDropTarget(_ zone: SidebarDropZone, row: AnyHashable, drag: SidebarDrag,
                           session: ProfileSession) -> some View {
        modifier(SidebarDropTargetModifier(zone: zone, row: row, drag: drag, session: session))
    }
}

private struct SidebarDropTargetModifier: ViewModifier {
    let zone: SidebarDropZone
    let row: AnyHashable
    let drag: SidebarDrag
    let session: ProfileSession
    @State private var height: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .onDrop(of: [.utf8PlainText], delegate: SidebarDropDelegate(
                zone: zone, row: row, height: height, drag: drag, session: session,
                animation: MotionRole.rowState.animation(reduceMotion: reduceMotion)))
            // The kit hides the separator on the cell it makes; this wrapper is the cell now, so it hides it again.
            .listRowSeparator(.hidden)
    }
}

/// The drop side of a sidebar row. The other rows make room for the line with the kit's row motion.
private struct SidebarDropDelegate: DropDelegate {
    let zone: SidebarDropZone
    let row: AnyHashable
    let height: CGFloat
    let drag: SidebarDrag
    let session: ProfileSession
    let animation: Animation?

    func validateDrop(info: DropInfo) -> Bool {
        drag.isDragging && info.hasItemsConforming(to: [.utf8PlainText])
    }

    func dropEntered(info: DropInfo) {
        _ = dropUpdated(info: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let item = drag.item else { return DropProposal(operation: .forbidden) }
        let hover = zone.hover(at: info.location.y, height: height, row: row)
        guard session.canDrop(item, at: hover.place) else {
            withAnimation(animation) { drag.leave(row) }
            return DropProposal(operation: .forbidden)
        }
        if drag.hover != hover { withAnimation(animation) { drag.propose(hover) } }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        withAnimation(animation) { drag.leave(row) }
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let item = drag.item else { return false }
        let place = drag.hover?.place ?? zone.hover(at: info.location.y, height: height, row: row).place
        var dropped = false
        withAnimation(animation) {
            dropped = session.drop(item, at: place)
            drag.end()
        }
        return dropped
    }
}

/// The line that shows where a dragged item will land, as a cell of its own between the rows, so the rows below it move
/// down to make room. ThemeKit has no insertion line: it is drawn here with the kit's selection marker (its colour and
/// its width) across the row's width.
struct InsertionLineRow: View {
    let placement: SidebarCellPlacement
    @Environment(\.designTokens) private var tokens

    static let rowID = "safira.insertionLine"

    var body: some View {
        WithColorRoles { roles in
            Capsule(style: .continuous)
                .fill(roles.selectionMarker)
                .frame(height: tokens.size.selectionMarker)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        }
        .sidebarCell(state: RowState(), placement: placement, hoverID: Self.rowID)
    }
}

/// The pinned area while it is empty and a Tab is being dragged: a row to drop the Tab on, which pins it.
struct PinDropZone: View {
    let isTargeted: Bool

    static let rowID = "safira.pinDropZone"

    var body: some View {
        SidebarRowContent(title: String(localized: "Drop Here to Pin", comment: "Sidebar: the empty pinned area while a Tab is dragged")) {
            Tile(.tintedSymbol("pin"))
        } trailing: {
            EmptyView()
        }
        .sidebarCell(state: RowState(isCurrent: isTargeted), placement: .free, hoverID: Self.rowID)
    }
}

/// The plain Tabs as the sidebar lists them, with the insertion line in its gap while a drag proposes one.
@MainActor
enum PlainTabCell: @MainActor Identifiable {
    case tab(SafiraSession.Tab, index: Int)
    case line

    var id: AnyHashable {
        switch self {
        case .tab(let tab, _): tab.id
        case .line: InsertionLineRow.rowID
        }
    }

    static func cells(of tabs: [SafiraSession.Tab], line: SidebarDropPlace?) -> [PlainTabCell] {
        var cells = tabs.enumerated().map { PlainTabCell.tab($0.element, index: $0.offset) }
        if case .tabs(let index)? = line { cells.insert(.line, at: max(0, min(index, cells.count))) }
        return cells
    }
}
