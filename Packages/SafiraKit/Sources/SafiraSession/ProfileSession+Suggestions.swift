// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// The Command bar's local suggestions. They come from this Profile's Tabs and its own history database, and nothing
/// here can start a request: no page is created or loaded, and no network type is used.
extension ProfileSession {
    /// The suggestions for the text typed in the Command bar: the Profile's open Tabs (active Space first), then
    /// the pages it visited, most recent first. A page that is open as a Tab is listed as the Tab only. Typing nothing
    /// suggests nothing.
    public func suggestions(for text: String, limit: Int = 8) async -> [CommandBarSuggestion] {
        guard limit > 0, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let open = openTabSuggestions(for: text)
        var suggestions = Array(open.prefix(limit))
        let openAddresses = Set(allTabs.compactMap(\.address))
        if let history, suggestions.count < limit {
            await recordedHistorySettled()
            do {
                // The open Tabs hide some of the matches, so ask for more than the room left.
                let found = try await history.searchHistory(text, limit: limit + openAddresses.count)
                suggestions += found.filter { !openAddresses.contains($0.url) }.prefix(limit - suggestions.count).map {
                    CommandBarSuggestion(kind: .history($0.url), title: $0.title ?? $0.url.absoluteString, address: $0.url)
                }
            } catch {
                onHistoryError?(error)
            }
        }
        return suggestions
    }

    private func openTabSuggestions(for text: String) -> [CommandBarSuggestion] {
        let ordered = spaces.sorted { ($0.id == activeSpaceID ? 0 : 1) < ($1.id == activeSpaceID ? 0 : 1) }
        return ordered.flatMap { space in
            space.allTabs.compactMap { tab -> CommandBarSuggestion? in
                guard let address = tab.address,
                      SuggestionText.matches(text, in: [tab.state.title ?? "", address.absoluteString]) else { return nil }
                let title = tab.state.title.flatMap { $0.isEmpty ? nil : $0 } ?? address.absoluteString
                return CommandBarSuggestion(kind: .openTab(tab.id), title: title, address: address, spaceEmoji: space.emoji)
            }
        }
    }
}
