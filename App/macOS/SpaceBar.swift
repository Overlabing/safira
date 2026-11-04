// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import SafiraSession
import SwiftUI

/// What the sidebar asks the window to do with Spaces: the window owns the sheets and alerts, so that the menu and the
/// sidebar open the same ones.
struct SpaceActions {
    /// Opens the Space editor: for a new Space when the identifier is nil.
    let edit: (SpaceID?) -> Void
    /// Asks before deleting a Space.
    let delete: (SpaceID) -> Void
}

/// The row of Space emoji at the bottom of the sidebar. A click shows the Space; its context menu renames, moves or
/// deletes it; the plus button adds a Space.
struct SpaceBar: View {
    let session: ProfileSession
    let actions: SpaceActions

    var body: some View {
        HStack(spacing: 2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(session.spaces.enumerated()), id: \.element.id) { index, space in
                        SpaceButton(space: space, index: index, session: session, actions: actions)
                    }
                }
            }
            Button {
                actions.edit(nil)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("New Space")
            .accessibilityLabel("New Space")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
    }
}

private struct SpaceButton: View {
    let space: SafiraSession.Space
    let index: Int
    let session: ProfileSession
    let actions: SpaceActions

    private var isActive: Bool { session.activeSpaceID == space.id }

    var body: some View {
        Button {
            session.selectSpace(space.id)
        } label: {
            Text(space.emoji)
                .font(.system(size: 16))
                .frame(width: 28, height: 28)
                .background(isActive ? Color.primary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.borderless)
        .help(space.name)
        .contextMenu {
            Button("Rename Space…") { actions.edit(space.id) }
            Divider()
            Button("Move Left") { session.moveSpace(space.id, by: -1) }
                .disabled(index == 0)
            Button("Move Right") { session.moveSpace(space.id, by: 1) }
                .disabled(index == session.spaces.count - 1)
            Divider()
            Button("Delete Space…") { actions.delete(space.id) }
                .disabled(!session.canDeleteSpace)
        }
        .accessibilityLabel(space.name)
        .accessibilityValue(String(localized: "\(index + 1) of \(session.spaces.count)"))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Rename Space") { actions.edit(space.id) }
        .accessibilityAction(named: "Move Left") { session.moveSpace(space.id, by: -1) }
        .accessibilityAction(named: "Move Right") { session.moveSpace(space.id, by: 1) }
        .accessibilityAction(named: "Delete Space") { actions.delete(space.id) }
    }
}

/// Names a new Space or renames one. The emoji field takes one character; the system's emoji picker (⌃⌘Space) works
/// in it.
struct SpaceEditor: View {
    let title: String
    let confirmTitle: String
    @State var name: String
    @State var emoji: String
    let save: (_ name: String, _ emoji: String) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Form {
                TextField("Name", text: $name)
                TextField("Emoji", text: $emoji)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) { save(name, emoji) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
