// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// One Space as the Space rail names it: no Tabs.
public struct SpaceSummary: Hashable, Sendable, Identifiable {
    public let id: SpaceID
    public var name: String
    public var emoji: String
    /// The Space's Theme; nil wears its Profile's.
    public var paletteID: String?

    public init(id: SpaceID, name: String, emoji: String, paletteID: String? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
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
