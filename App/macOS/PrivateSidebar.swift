// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import SafiraSession
import SwiftUI

/// The sidebar of a Private window: a "Private" header naming the Profile it is attached to, and the list of its Tabs.
/// There is no Profile switcher and no row of Spaces. The dark purple tint is what tells it from the Main window's.
struct PrivateSidebar: View {
    let session: ProfileSession
    let parent: Profile
    let showPage: () -> Void

    static let tint = Color(red: 0.20, green: 0.11, blue: 0.33)

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabList
        }
        .frame(minWidth: 180)
        .background(Self.tint)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Private", systemImage: "eye.slash.fill")
                .font(.headline)
            Text(verbatim: "\(parent.symbol) \(parent.name)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Private window, attached to the Profile \(parent.name). Nothing is saved."))
        .accessibilityAddTraits(.isHeader)
    }

    private var tabList: some View {
        List(selection: selection) {
            ForEach(session.tabs) { tab in
                PrivateTabRow(
                    tab: tab,
                    position: (session.tabs.firstIndex { $0.id == tab.id } ?? 0) + 1,
                    count: session.tabs.count,
                    session: session
                )
                .tag(tab.id)
            }
            .onMove { source, destination in
                guard let from = source.first else { return }
                session.move(session.tabs[from].id, to: destination > from ? destination - 1 : destination)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
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

private struct PrivateTabRow: View {
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

    private var accessibilityState: String {
        var parts: [String] = []
        if tab.state.isLoading { parts.append(String(localized: "Loading")) }
        if tab.state.isPlayingMedia { parts.append(String(localized: "Playing media")) }
        parts.append(String(localized: "\(position) of \(count)"))
        return parts.joined(separator: ", ")
    }
}
