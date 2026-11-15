// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DesignKit
import SwiftUI

extension View {
    /// A group of a Settings pane on ThemeKit's layer surface, as the sidebar groups a folder's rows: no opaque system
    /// box, so the Theme's gradient shows through in light, dark and Increase Contrast (which outlines it).
    func settingsGroup() -> some View {
        modifier(SettingsGroup())
    }

    /// A list or form of a Settings pane whose content fades out at its top and bottom edges instead of being cut by a
    /// hard line, inset so that nothing is faded while it is scrolled to an end. The list draws no background of its
    /// own: the group or the window's gradient is under it.
    func settingsScrollEdges() -> some View {
        modifier(SettingsScrollEdges())
    }

    /// A row of a selectable list in a `settingsGroup()`: the kit's row background (selection and hover in the Theme's
    /// colour, as in the sidebar) instead of the system's grey or accent platter. The list needs
    /// `listSelectionPlatterOff()`.
    func settingsListRow(isSelected: Bool, id: some Hashable) -> some View {
        modifier(SettingsListRow(isSelected: isSelected, id: AnyHashable(id)))
    }
}

private struct SettingsListRow: ViewModifier {
    @Environment(\.designTokens) private var tokens
    let isSelected: Bool
    let id: AnyHashable

    func body(content: Content) -> some View {
        let spacing = tokens.spacing
        content
            .padding(.horizontal, spacing.layerInset + spacing.rowInsetHorizontal)
            .padding(.vertical, spacing.rowInsetVertical + spacing.rowGap / 2)
            .listRowCell(state: RowState(isSelected: isSelected), placement: .layer(level: 1), hoverID: id)
    }
}

private struct SettingsGroup: ViewModifier {
    @Environment(\.designTokens) private var tokens

    func body(content: Content) -> some View {
        content
            .surface(.layer, in: RoundedRectangle(cornerRadius: tokens.radius.layer, style: .continuous))
    }
}

private struct SettingsScrollEdges: ViewModifier {
    private let fade = DesignTokens.Spacing.m

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .contentMargins(.vertical, fade, for: .scrollContent)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: fade)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: fade)
                }
            }
    }
}
