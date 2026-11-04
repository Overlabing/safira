// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Observation
import SafiraCore
import SwiftUI

/// What the Command bar's suggestion list shows. The window sets it as the user types.
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

/// The list under the Command bar. The keyboard stays in the text field: arrows move the highlight and Return opens it.
struct CommandBarSuggestionList: View {
    let model: CommandBarSuggestionModel
    let choose: (CommandBarSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Row(suggestion: suggestion, isHighlighted: model.highlight.index == index) { choose(suggestion) }
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .padding(.horizontal, 8)
        .padding(.bottom, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggestions")
    }

    private struct Row: View {
        let suggestion: CommandBarSuggestion
        let isHighlighted: Bool
        let choose: () -> Void

        var body: some View {
            Button(action: choose) {
                HStack(spacing: 8) {
                    Image(systemName: isOpenTab ? "macwindow" : "clock")
                        .foregroundStyle(isHighlighted ? .primary : .secondary)
                        .frame(width: 18)
                    Text(suggestion.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(suggestion.address.absoluteString)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .layoutPriority(-1)
                    Spacer(minLength: 0)
                    if let emoji = suggestion.spaceEmoji {
                        Text("Switch to Tab").foregroundStyle(.secondary)
                        Text(verbatim: emoji)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHighlighted ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(suggestion.title)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(isHighlighted ? [.isButton, .isSelected] : .isButton)
        }

        private var isOpenTab: Bool {
            if case .openTab = suggestion.kind { true } else { false }
        }

        private var accessibilityValue: String {
            let kind = isOpenTab ? String(localized: "Open Tab") : String(localized: "History")
            return kind + ", " + suggestion.address.absoluteString
        }
    }
}

/// The list's hosting view never takes the keyboard focus, so clicking a suggestion leaves the Command bar's text
/// field editing.
final class CommandBarSuggestionHostingView: NSHostingView<CommandBarSuggestionList> {
    override var acceptsFirstResponder: Bool { false }
}
