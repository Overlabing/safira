// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DesignKit
import SafiraCore
import SafiraSession
import SwiftUI

/// What the sidebar asks the window to do with Folders: the window owns the sheets, so that the menu and the sidebar
/// open the same one.
struct FolderActions {
    /// Opens the naming sheet for a new Folder, inside the given Folder or at the top of the pinned area.
    let create: (FolderID?) -> Void
    let rename: (FolderID) -> Void
}

/// The active Space's pinned area: its Pinned tabs and its Folders. An open Folder's content sits on one panel, drawn a
/// cell at a time (`SidebarCellPlacement.panel`); a Folder inside a Folder is indented one level in the same panel.
/// While a drag proposes a place in it, the insertion line is a cell of its own there; while a Tab is dragged and the
/// area is empty, `PinDropZone` stands in for it.
struct PinnedSection: View {
    let session: ProfileSession
    let focus: ColumnFocus
    let actions: FolderActions
    let drag: SidebarDrag

    var body: some View {
        if session.pinnedItems.isEmpty, drag.isDragging {
            PinDropZone(isTargeted: drag.hover?.place == .pinned(folder: nil, index: 0))
                .sidebarDropTarget(.gap(.pinned(folder: nil, index: 0)), row: PinDropZone.rowID, drag: drag,
                                   session: session)
        } else {
            ForEach(PinnedCell.cells(of: session.pinnedItems, line: drag.linePlace)) { cell in
                switch cell.content {
                case .item(.tab(let tab), let container, let index):
                    pinnedTab(tab, placement: cell.placement)
                        .sidebarDropTarget(.row(above: .pinned(folder: container, index: index),
                                                below: .pinned(folder: container, index: index + 1)),
                                           row: cell.id, drag: drag, session: session)
                case .item(.folder(let folder), let container, let index):
                    PinnedFolder(folder: folder, session: session, actions: actions, drag: drag,
                                 placement: cell.placement)
                        .sidebarDropTarget(
                            .folder(folder.id, above: .pinned(folder: container, index: index),
                                    into: .pinned(folder: folder.id, index: folder.items.count),
                                    below: folder.isExpanded ? .pinned(folder: folder.id, index: 0)
                                                             : .pinned(folder: container, index: index + 1)),
                            row: cell.id, drag: drag, session: session)
                case .line(let place):
                    InsertionLineRow(placement: cell.placement)
                        .sidebarDropTarget(.gap(place), row: cell.id, drag: drag, session: session)
                }
            }
        }
    }

    private func pinnedTab(_ tab: SafiraSession.Tab, placement: SidebarCellPlacement) -> some View {
        let pinned = session.activeSpace.pinnedTabs
        return TabRowView(tab: tab, icons: session.siteIcons, isSelected: session.sidebarSelection == .tab(tab.id),
                          isListFocused: focus.isListFocused,
                          placement: placement, position: (pinned.firstIndex { $0.id == tab.id } ?? 0) + 1,
                          count: session.activeSpace.allTabs.count,
                          select: { session.select(tab.id) }, close: { session.close(tab.id) },
                          clickIcon: { session.clickIcon(of: tab.id) })
            .sidebarDragSource(.tab(tab.id), drag: drag)
            .contextMenu { TabMenu(tab: tab, session: session) }
    }
}

/// The pinned area flattened into the `List`'s cells: every Pinned tab and Folder in order, an open Folder's content
/// right after it in that Folder's panel, the panel's first and last cells marked so its ends are rounded. Each item
/// keeps the Folder that holds it (nil for the top of the area) and its index there, which name the gaps around it.
/// `line` puts the insertion line in its gap; a gap inside a closed Folder shows none.
@MainActor
struct PinnedCell: @MainActor Identifiable {
    enum Content {
        case item(PinnedItem, container: FolderID?, index: Int)
        case line(SidebarDropPlace)
    }

    let content: Content
    let placement: SidebarCellPlacement

    var id: AnyHashable {
        switch content {
        case .item(let item, _, _): item.id
        case .line: InsertionLineRow.rowID
        }
    }

    static func cells(of items: [PinnedItem], line: SidebarDropPlace? = nil) -> [PinnedCell] {
        var cells: [PinnedCell] = []
        for (index, item) in items.enumerated() {
            if let line, line == .pinned(folder: nil, index: index) {
                cells.append(PinnedCell(content: .line(line), placement: .free))
            }
            cells.append(PinnedCell(content: .item(item, container: nil, index: index), placement: .free))
            guard case .folder(let folder) = item, folder.isExpanded else { continue }
            let inside = contents(of: folder, level: 1, line: line)
            cells += inside.enumerated().map { offset, cell in
                PinnedCell(content: cell.content, placement: .panel(level: cell.level, isFirst: offset == 0,
                                                                    isLast: offset == inside.count - 1))
            }
        }
        if let line, line == .pinned(folder: nil, index: items.count) {
            cells.append(PinnedCell(content: .line(line), placement: .free))
        }
        return cells
    }

    private static func contents(of folder: Folder, level: Int,
                                 line: SidebarDropPlace?) -> [(content: Content, level: Int)] {
        var cells: [(content: Content, level: Int)] = []
        for (index, item) in folder.items.enumerated() {
            if let line, line == .pinned(folder: folder.id, index: index) { cells.append((.line(line), level)) }
            cells.append((.item(item, container: folder.id, index: index), level))
            if case .folder(let inner) = item, inner.isExpanded {
                cells += contents(of: inner, level: level + 1, line: line)
            }
        }
        if let line, line == .pinned(folder: folder.id, index: folder.items.count) { cells.append((.line(line), level)) }
        return cells
    }
}

private struct PinnedFolder: View {
    let folder: Folder
    let session: ProfileSession
    let actions: FolderActions
    let drag: SidebarDrag
    let placement: SidebarCellPlacement
    @Environment(\.designTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WithColorRoles { roles in
            SidebarRowContent(title: folder.name) {
                Tile(.tintedSymbol(folder.isExpanded ? "folder.fill" : "folder"))
            } trailing: {
                HStack(spacing: tokens.spacing.pillActionGap) {
                    Text(folder.items.count, format: .number).role(tokens.type.count).foregroundStyle(roles.secondaryText)
                    Image(systemName: "chevron.right")
                        .font(tokens.type.accessory.font)
                        .foregroundStyle(roles.secondaryText)
                        .rotationEffect(folder.isExpanded ? .degrees(tokens.size.disclosureDegrees) : .zero)
                        .animation(MotionRole.indicatorRotation.animation(reduceMotion: reduceMotion), value: folder.isExpanded)
                }
            }
        }
        .onTapGesture { session.setFolderExpanded(folder.id, !folder.isExpanded) }
        .sidebarDragSource(.folder(folder.id), drag: drag)
        .contextMenu {
            Button("New Folder Inside…") { actions.create(folder.id) }
            Button("Rename Folder…") { actions.rename(folder.id) }
            Divider()
            Button("Delete Folder") { session.deleteFolder(folder.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(folder.isExpanded ? String(localized: "Expanded", comment: "VoiceOver value of a Folder")
                                              : String(localized: "Collapsed", comment: "VoiceOver value of a Folder"))
        .accessibilityAction(.default) { session.setFolderExpanded(folder.id, !folder.isExpanded) }
        .accessibilityAction(named: folder.isExpanded ? String(localized: "Collapse", comment: "VoiceOver action of a Folder")
                                                      : String(localized: "Expand", comment: "VoiceOver action of a Folder")) {
            session.setFolderExpanded(folder.id, !folder.isExpanded)
        }
        .accessibilityAction(named: "Rename Folder") { actions.rename(folder.id) }
        .accessibilityAction(named: "Delete Folder") { session.deleteFolder(folder.id) }
        .sidebarCell(state: RowState(isCurrent: drag.hover?.into == folder.id), placement: placement, hoverID: folder.id)
    }
}

/// Names a new Folder or renames one. The field has the keyboard when the sheet opens, with the current name selected,
/// so what the user types replaces it; Return saves what the field holds.
struct FolderEditor: View {
    let title: String
    let confirmTitle: String
    @State var name: String
    let save: (_ name: String) -> Void
    let cancel: () -> Void
    @FocusState private var nameHasFocus: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Form {
                TextField("Name", text: $name)
                    .focused($nameHasFocus)
                    .onSubmit(commit)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 320)
        .task {
            nameHasFocus = true
            // The field editor exists once the field has focus.
            try? await Task.sleep(for: .milliseconds(50))
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    private func commit() {
        if canSave { save(name) }
    }
}
