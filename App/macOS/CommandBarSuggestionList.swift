// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DesignKit
import Observation
import SafiraCore
import SwiftUI

/// What the Command bar's suggestion list shows. The Command bar sets it as the user types.
@MainActor
@Observable
final class CommandBarSuggestionModel {
    private(set) var suggestions: [CommandBarSuggestion] = []
    private(set) var highlight = SuggestionHighlight(typing: "", count: 0)

    var highlighted: CommandBarSuggestion? {
        highlight.index.map { suggestions[$0] }
    }

    func show(_ suggestions: [CommandBarSuggestion], typing text: String) {
        self.suggestions = suggestions
        highlight = SuggestionHighlight(typing: text, count: suggestions.count)
    }

    func clear() {
        suggestions = []
        highlight = SuggestionHighlight(typing: "", count: 0)
    }

    func moveDown() {
        highlight.moveDown(count: suggestions.count)
    }

    func moveUp() {
        highlight.moveUp(count: suggestions.count)
    }
}

/// The list under the Command bar's field, in the kit's rows. The keyboard stays in the text field: arrows move the
/// highlight (the row's selection) and Return opens it.
struct CommandBarSuggestionList: View {
    let model: CommandBarSuggestionModel
    let choose: (CommandBarSuggestion) -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                SuggestionRow(suggestion: suggestion, isHighlighted: model.highlight.index == index) { choose(suggestion) }
            }
        }
        .padding(.vertical, tokens.spacing.rowGap)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
    }
}

private struct SuggestionRow: View {
    let suggestion: CommandBarSuggestion
    let isHighlighted: Bool
    let choose: () -> Void
    @State private var isHovered = false
    @Environment(\.designTokens) private var tokens

    var body: some View {
        WithColorRoles { roles in
            ListRow(suggestion.title, details: [AddressDisplay(suggestion.address).hostAndPath],
                    state: RowState(isSelected: isHighlighted, isHovered: isHovered)) {
                Tile(.tintedSymbol(isOpenTab ? "macwindow" : "clock"), size: .compact)
            } trailing: {
                if let emoji = suggestion.spaceEmoji {
                    HStack(spacing: tokens.spacing.pillActionGap) {
                        Text("Switch to Tab").role(tokens.type.count).foregroundStyle(roles.secondaryText)
                        Text(verbatim: emoji)
                    }
                }
            }
            .onHover { isHovered = $0 }
            .onTapGesture(perform: choose)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(suggestion.title)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(.default, choose)
        }
    }

    private var isOpenTab: Bool {
        if case .openTab = suggestion.kind { true } else { false }
    }

    private var accessibilityValue: String {
        let kind = isOpenTab ? String(localized: "Open Tab", comment: "Command bar: kind of a suggestion, read by VoiceOver") : String(localized: "History", comment: "Command bar: kind of a suggestion, read by VoiceOver")
        return kind + ", " + suggestion.address.absoluteString
    }
}
