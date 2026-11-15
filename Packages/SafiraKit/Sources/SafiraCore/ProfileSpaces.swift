// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Spaces

/// One Space as the Space rail names it: no Tabs.
public struct SpaceSummary: Hashable, Sendable, Identifiable {
    public let id: SpaceID
    public var name: String
    public var icon: SpaceGlyph
    /// The Space's Theme; nil wears its Profile's.
    public var paletteID: String?

    public init(id: SpaceID, name: String, icon: SpaceGlyph, paletteID: String? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.paletteID = paletteID
    }
}

/// A Profile's Spaces in sidebar order, and the one it was last on: what the Space rail shows of a Profile, read
/// without loading it.
public struct ProfileSpaces: Hashable, Sendable {
    public var spaces: [SpaceSummary]
    /// The Profile's last active Space, where switching to it lands; nil when it has none saved.
    public var lastSpaceID: SpaceID?

    public init(spaces: [SpaceSummary] = [], lastSpaceID: SpaceID? = nil) {
        self.spaces = spaces
        self.lastSpaceID = lastSpaceID
    }
}

/// How a Space is marked in a line of text, a Command bar suggestion or a Link picker tile: its emoji, its SF Symbol,
/// or the initial of its name.
public enum SpaceMark: Hashable, Sendable {
    case text(String)
    case symbol(String)

    public init(_ icon: SpaceGlyph, name: String) {
        switch icon {
        case .emoji(let emoji): self = .text(emoji)
        case .symbol(let symbol): self = .symbol(symbol)
        case .initial: self = .text(name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "")
        }
    }
}
