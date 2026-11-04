// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import SafiraSession
import SwiftUI

/// The sidebar: the active Space's name, its pinned area with its Folders, the list of its other Tabs, and the row of
/// Spaces at the bottom. In the list, arrow keys move the selection, which shows the Tab; Delete closes it; Return or
/// Escape goes to its page; Tabs can be dragged to reorder, and Pinned tabs and Folders into Folders.
struct TabSidebar: View {
    let session: ProfileSession
    let spaceActions: SpaceActions
    let folderActions: FolderActions
    let showPage: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(verbatim: "\(session.activeSpace.emoji) \(session.activeSpace.name)")
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityLabel(String(localized: "Space: \(session.activeSpace.name)"))
                .accessibilityAddTraits(.isHeader)
            tabList
            Divider()
            SpaceBar(session: session, actions: spaceActions)
        }
        .frame(minWidth: 180)
    }

    private var tabList: some View {
        List(selection: selection) {
            if !session.pinnedItems.isEmpty {
                Section {
                    ForEach(PinnedRow.rows(session.pinnedItems)) { row in
                        switch row.content {
                        case .folder(let folder, let depth):
                            FolderRow(folder: folder, depth: depth, session: session, actions: folderActions)
                        case .tab(let tab, let depth):
                            let pinned = session.activeSpace.pinnedTabs
                            TabRow(
                                tab: tab,
                                position: (pinned.firstIndex { $0.id == tab.id } ?? 0) + 1,
                                count: pinned.count,
                                depth: depth,
                                session: session
                            )
                            .tag(tab.id)
                        }
                    }
                } header: {
                    Text("Pinned")
                        .dropDestination(for: String.self) { texts, _ in
                            guard let item = texts.first.flatMap(PinnedDrag.item(from:)) else { return false }
                            return session.movePinned(item, into: nil)
                        }
                }
            }
            Section {
                ForEach(session.tabs) { tab in
                    TabRow(
                        tab: tab,
                        position: (session.tabs.firstIndex { $0.id == tab.id } ?? 0) + 1,
                        count: session.tabs.count,
                        depth: 0,
                        session: session
                    )
                    .tag(tab.id)
                }
                .onMove { source, destination in
                    guard let from = source.first else { return }
                    // SwiftUI gives the place before the move; the session takes the place after it.
                    session.move(session.tabs[from].id, to: destination > from ? destination - 1 : destination)
                }
            } header: {
                if !session.pinnedItems.isEmpty {
                    Text("Tabs")
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Tabs")
        .onDeleteCommand {
            session.closeSelectedTab()
        }
        .onKeyPress(.return) {
            showPage()
            return .handled
        }
        .onKeyPress(.escape) {
            showPage()
            return .handled
        }
    }

    private var selection: Binding<TabID?> {
        Binding(
            get: { session.selectedTabID },
            set: { id in
                if let id { session.select(id) }
            }
        )
    }
}

private struct TabRow: View {
    let tab: SafiraSession.Tab
    let position: Int
    let count: Int
    let depth: Int
    let session: ProfileSession
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if tab.state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)
            if tab.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if tab.state.isPlayingMedia {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(.secondary)
            }
            if isHovered {
                Button {
                    session.close(tab.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close Tab")
            }
        }
        .padding(.leading, CGFloat(depth) * 14)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .modifier(PinnedDragSource(tab: tab, session: session))
        .contextMenu {
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { session.togglePin(tab.id) }
            Divider()
            Button("Move Up") { session.move(tab.id, by: -1) }
                .disabled(!session.canMove(tab.id, by: -1))
            Button("Move Down") { session.move(tab.id, by: 1) }
                .disabled(!session.canMove(tab.id, by: 1))
            Divider()
            Button("Close Tab") { session.close(tab.id) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(session.selectedTabID == tab.id ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: tab.isPinned ? "Unpin Tab" : "Pin Tab") { session.togglePin(tab.id) }
        .accessibilityAction(named: "Close Tab") { session.close(tab.id) }
        .accessibilityAction(named: "Move Up") { session.move(tab.id, by: -1) }
        .accessibilityAction(named: "Move Down") { session.move(tab.id, by: 1) }
    }

    private var title: String {
        if let title = tab.state.title, !title.isEmpty { return title }
        return tab.address?.host() ?? String(localized: "New Tab")
    }

    /// The Tab's state then its place, as VoiceOver reads it after the title: "Loading, Playing media, 2 of 5".
    private var accessibilityState: String {
        var parts: [String] = []
        if tab.state.isLoading { parts.append(String(localized: "Loading")) }
        if tab.state.isPlayingMedia { parts.append(String(localized: "Playing media")) }
        if tab.isPinned { parts.append(String(localized: "Pinned")) }
        parts.append(String(localized: "\(position) of \(count)"))
        return parts.joined(separator: ", ")
    }
}

/// A Pinned tab can be dragged into a Folder, or before another Pinned tab. A plain Tab is left to the list's own
/// reordering: it is not offered to any Folder.
private struct PinnedDragSource: ViewModifier {
    let tab: SafiraSession.Tab
    let session: ProfileSession

    func body(content: Content) -> some View {
        if tab.isPinned {
            content
                .draggable(PinnedDrag.text(for: .tab(tab.id)))
                .dropDestination(for: String.self) { texts, _ in
                    guard let item = texts.first.flatMap(PinnedDrag.item(from:)) else { return false }
                    return session.movePinned(item, before: .tab(tab.id))
                }
        } else {
            content
        }
    }
}
