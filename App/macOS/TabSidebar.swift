// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import SafiraSession
import SwiftUI

/// The sidebar list of the Tabs of the single Space. Arrow keys move the selection, which shows the Tab; Delete closes
/// it; Return goes to its page; rows can be dragged to reorder.
struct TabSidebar: View {
    let session: ProfileSession
    let showPage: () -> Void

    var body: some View {
        List(selection: selection) {
            ForEach(session.tabs) { tab in
                TabRow(
                    tab: tab,
                    position: (session.tabs.firstIndex { $0.id == tab.id } ?? 0) + 1,
                    count: session.tabs.count,
                    session: session
                )
                .tag(tab.id)
            }
            .onMove { source, destination in
                guard let from = source.first else { return }
                // SwiftUI gives the place before the move; the session takes the place after it.
                session.move(session.tabs[from].id, to: destination > from ? destination - 1 : destination)
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
        .frame(minWidth: 180)
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
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Move Up") { session.move(tab.id, by: -1) }
                .disabled(position == 1)
            Button("Move Down") { session.move(tab.id, by: 1) }
                .disabled(position == count)
            Divider()
            Button("Close Tab") { session.close(tab.id) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityState)
        .accessibilityAddTraits(session.selectedTabID == tab.id ? [.isButton, .isSelected] : .isButton)
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
        parts.append(String(localized: "\(position) of \(count)"))
        return parts.joined(separator: ", ")
    }
}
