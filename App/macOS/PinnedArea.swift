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

/// What a drag carries: a Pinned tab or a Folder. Plain Tabs are never offered, and a drop that does not parse is
/// refused, so text dragged in from elsewhere does nothing.
enum PinnedDrag {
    static func text(for item: PinnedItemID) -> String {
        switch item {
        case .tab(let id): "safira-tab:\(id.rawValue.uuidString)"
        case .folder(let id): "safira-folder:\(id.rawValue.uuidString)"
        }
    }

    static func item(from text: String) -> PinnedItemID? {
        if let id = text.removingPrefix("safira-tab:").flatMap(UUID.init(uuidString:)) {
            return .tab(TabID(rawValue: id))
        }
        if let id = text.removingPrefix("safira-folder:").flatMap(UUID.init(uuidString:)) {
            return .folder(FolderID(rawValue: id))
        }
        return nil
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

/// The active Space's pinned area: its Pinned tabs and its Folders. An open Folder's content sits on one panel, drawn a
/// cell at a time (`SidebarCellPlacement.panel`); a Folder inside a Folder is indented one level in the same panel.
struct PinnedSection: View {
    let session: ProfileSession
    let focus: ColumnFocus
    let actions: FolderActions

    var body: some View {
        ForEach(PinnedCell.cells(of: session.pinnedItems)) { cell in
            switch cell.item {
            case .tab(let tab):
                pinnedTab(tab, placement: cell.placement)
            case .folder(let folder):
                PinnedFolder(folder: folder, session: session, actions: actions, placement: cell.placement)
            }
        }
    }

    private func pinnedTab(_ tab: SafiraSession.Tab, placement: SidebarCellPlacement) -> some View {
        let pinned = session.activeSpace.pinnedTabs
        return TabRowView(tab: tab, icons: session.siteIcons, isSelected: session.sidebarSelection == .tab(tab.id),
                          isListFocused: focus.isListFocused,
                          placement: placement, position: (pinned.firstIndex { $0.id == tab.id } ?? 0) + 1,
                          count: session.activeSpace.allTabs.count,
                          select: { session.select(tab.id) }, close: { session.close(tab.id) })
            .modifier(TabDrag(tab: tab, session: session))
            .contextMenu { TabMenu(tab: tab, session: session) }
    }
}

/// The pinned area flattened into the `List`'s cells: every Pinned tab and Folder in order, an open Folder's content
/// right after it in that Folder's panel, the panel's first and last cells marked so its ends are rounded.
@MainActor
struct PinnedCell: @MainActor Identifiable {
    let item: PinnedItem
    let placement: SidebarCellPlacement

    var id: PinnedItemID { item.id }

    static func cells(of items: [PinnedItem]) -> [PinnedCell] {
        items.flatMap { item -> [PinnedCell] in
            let head = PinnedCell(item: item, placement: .free)
            guard case .folder(let folder) = item, folder.isExpanded else { return [head] }
            let inside = contents(of: folder, level: 1)
            return [head] + inside.enumerated().map { index, cell in
                PinnedCell(item: cell.item, placement: .panel(level: cell.level, isFirst: index == 0,
                                                              isLast: index == inside.count - 1))
            }
        }
    }

    private static func contents(of folder: Folder, level: Int) -> [(item: PinnedItem, level: Int)] {
        folder.items.flatMap { item -> [(item: PinnedItem, level: Int)] in
            guard case .folder(let inner) = item, inner.isExpanded else { return [(item, level)] }
            return [(item, level)] + contents(of: inner, level: level + 1)
        }
    }
}

private struct PinnedFolder: View {
    let folder: Folder
    let session: ProfileSession
    let actions: FolderActions
    let placement: SidebarCellPlacement
    @State private var isDropTarget = false
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
        .draggable(PinnedDrag.text(for: .folder(folder.id)))
        .dropDestination(for: String.self, action: { texts, _ in
            guard let item = texts.first.flatMap(PinnedDrag.item(from:)) else { return false }
            return session.movePinned(item, into: folder.id)
        }, isTargeted: { isDropTarget = $0 })
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
        .sidebarCell(state: RowState(isCurrent: isDropTarget), placement: placement, hoverID: folder.id)
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
