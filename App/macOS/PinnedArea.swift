// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

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

/// A row of the pinned area, flattened from the tree of Folders: a collapsed Folder hides what it holds.
struct PinnedRow: Identifiable {
    enum Content {
        case folder(Folder, depth: Int)
        case tab(SafiraSession.Tab, depth: Int)
    }

    let id: PinnedItemID
    let content: Content

    @MainActor
    static func rows(_ items: [PinnedItem], depth: Int = 0) -> [PinnedRow] {
        items.flatMap { item -> [PinnedRow] in
            switch item {
            case .tab(let tab):
                [PinnedRow(id: .tab(tab.id), content: .tab(tab, depth: depth))]
            case .folder(let folder):
                [PinnedRow(id: .folder(folder.id), content: .folder(folder, depth: depth))]
                    + (folder.isExpanded ? rows(folder.items, depth: depth + 1) : [])
            }
        }
    }
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

struct FolderRow: View {
    let folder: Folder
    let depth: Int
    let session: ProfileSession
    let actions: FolderActions
    @State private var isDropTarget = false
    @Environment(\.sidebarSecondary) private var secondary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .rotationEffect(.degrees(folder.isExpanded ? 90 : 0))
                .foregroundStyle(secondary)
                .frame(width: 12)
            Image(systemName: folder.isExpanded ? "folder.fill" : "folder")
                .foregroundStyle(secondary)
            Text(folder.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .background(isDropTarget ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 4))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(folder.name)
        .accessibilityValue(folder.isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
        .accessibilityAddTraits(.isButton)
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
