// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// One local suggestion of the Command bar. It comes from the Active profile's open Tabs or history, never from the
/// network.
public struct CommandBarSuggestion: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// An open Tab of the Profile, in any of its Spaces: choosing it shows that Tab.
        case openTab(TabID)
        /// A page the Profile visited: choosing it loads the address.
        case history(URL)
    }

    public let kind: Kind
    public let title: String
    public let address: URL
    /// The emoji of the Space holding an open Tab; nil for a history entry.
    public let spaceEmoji: String?

    public init(kind: Kind, title: String, address: URL, spaceEmoji: String? = nil) {
        self.kind = kind
        self.title = title
        self.address = address
        self.spaceEmoji = spaceEmoji
    }

    public var id: Kind { kind }

    /// The SF Symbol shown while no icon is cached for the suggestion's site: a globe for an open Tab's address, a clock
    /// for a page from history.
    public var fallbackSymbol: String {
        switch kind {
        case .openTab: "globe"
        case .history: "clock"
        }
    }
}

/// How typed text is compared with the text of Tabs and history: letter case and accents are ignored.
public enum SuggestionText {
    /// The text without letter case or accents, so that "CAFÉ" and "cafe" are the same.
    public static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Whether every word of `query` appears in `fields`, anywhere in a word: "hub" finds "GitHub".
    public static func matches(_ query: String, in fields: [String]) -> Bool {
        let words = folded(query).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return false }
        let haystack = fields.map(folded).joined(separator: " ")
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// Which suggestion Return opens. Nil means none: Return submits the typed text as it is.
public struct SuggestionHighlight: Equatable, Sendable {
    public private(set) var index: Int?

    /// The first suggestion is highlighted when the text is a search, so that typing part of a Tab's title and pressing
    /// Return jumps to it. Text that is an address is submitted as typed unless the user moves to a suggestion.
    public init(typing text: String, count: Int) {
        if count > 0, case .search? = CommandBarInput(text) {
            index = 0
        }
    }

    /// Down goes through the suggestions, then back to the typed text.
    public mutating func moveDown(count: Int) {
        guard count > 0 else { index = nil; return }
        switch index {
        case nil: index = 0
        case let current? where current + 1 < count: index = current + 1
        default: index = nil
        }
    }

    /// Up goes from the typed text to the last suggestion.
    public mutating func moveUp(count: Int) {
        guard count > 0 else { index = nil; return }
        switch index {
        case nil: index = count - 1
        case 0?: index = nil
        case let current?: index = current - 1
        }
    }
}
