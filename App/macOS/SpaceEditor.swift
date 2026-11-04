// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import ColorUI
import DesignKit
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

/// Names a new Space or edits one, and picks its Theme from the Palette. The emoji field takes one character; the
/// system's emoji picker (⌃⌘Space) works in it.
struct SpaceEditor: View {
    let title: String
    let confirmTitle: String
    @State var name: String
    @State var emoji: String
    @State var paletteID: String
    let save: (_ name: String, _ emoji: String, _ paletteID: String) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Form {
                TextField("Name", text: $name)
                TextField("Emoji", text: $emoji)
                LabeledContent("Theme") { PalettePicker(selection: $paletteID) }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) { save(name, emoji, paletteID) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}

/// The Palette's Themes as swatches, one selected: the picker of the Profile and Space editors.
struct PalettePicker: View {
    @Binding var selection: String
    @Environment(\.designTokens) private var tokens

    var body: some View {
        HStack(spacing: tokens.spacing.pillActionGap) {
            ForEach(ThemeCatalog.palette.themes) { theme in
                Button {
                    selection = theme.id
                } label: {
                    ThemeSwatch(theme, isSelected: selection == theme.id)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme")
    }
}
