// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// A Profile: the security boundary that owns its own logins, history and search settings.
public struct Profile: Hashable, Sendable {
    public let id: ProfileID
    public var name: String
    /// Nil until the user picks one: no search engine is ever preselected.
    public var searchEngine: SearchEngine?

    public init(id: ProfileID, name: String, searchEngine: SearchEngine? = nil) {
        self.id = id
        self.name = name
        self.searchEngine = searchEngine
    }
}
