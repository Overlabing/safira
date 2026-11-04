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

/// The active Space's pinned area: its Pinned tabs and its Folders, each Folder a kit `FolderRow` whose open content
/// sits on one `LayerPanel`; a Folder inside a Folder is indented one level in the same panel.
struct PinnedSection: View {
    let session: ProfileSession
    let focus: ColumnFocus
    let actions: FolderActions

    var body: some View {
        ForEach(session.pinnedItems) { item in
            switch item {
            case .tab(let tab):
                pinnedTab(tab, placement: .free(firstInSection: false))
            case .folder(let folder):
                PinnedFolder(folder: folder, session: session, actions: actions)
                if folder.isExpanded, !folder.items.isEmpty {
                    LayerPanel { contents(of: folder, level: 1) }
                }
            }
        }
    }

    private func contents(of folder: Folder, level: Int) -> AnyView {
        AnyView(ForEach(folder.items) { item in
            switch item {
            case .tab(let tab):
                pinnedTab(tab, placement: .layer(level: level))
            case .folder(let inner):
                PinnedFolder(folder: inner, session: session, actions: actions)
                if inner.isExpanded { contents(of: inner, level: level + 1) }
            }
        })
    }

    private func pinnedTab(_ tab: SafiraSession.Tab, placement: RowPlacement) -> some View {
        let pinned = session.activeSpace.pinnedTabs
        return TabRowView(tab: tab, isSelected: session.selectedTabID == tab.id, isListFocused: focus.isListFocused,
                          placement: placement, position: (pinned.firstIndex { $0.id == tab.id } ?? 0) + 1,
                          count: session.activeSpace.allTabs.count,
                          select: { session.select(tab.id) }, close: { session.close(tab.id) })
            .modifier(TabDrag(tab: tab, session: session))
            .contextMenu { TabMenu(tab: tab, session: session) }
    }
}

private struct PinnedFolder: View {
    let folder: Folder
    let session: ProfileSession
    let actions: FolderActions
    @State private var isHovered = false
    @State private var isDropTarget = false

    var body: some View {
        FolderRow(folder.name, count: folder.items.count, isOpen: folder.isExpanded,
                  state: RowState(isCurrent: isDropTarget, isHovered: isHovered),
                  symbol: folder.isExpanded ? "folder.fill" : "folder")
            .onHover { isHovered = $0 }
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
            .accessibilityAction(.default) { session.setFolderExpanded(folder.id, !folder.isExpanded) }
            .accessibilityAction(named: folder.isExpanded ? "Collapse" : "Expand") {
                session.setFolderExpanded(folder.id, !folder.isExpanded)
            }
            .accessibilityAction(named: "Rename Folder") { actions.rename(folder.id) }
            .accessibilityAction(named: "Delete Folder") { session.deleteFolder(folder.id) }
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
