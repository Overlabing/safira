// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// A Profile: the security boundary that owns its own logins, history and search settings. These fields are the
/// Profile's entry in the app's list of Profiles; what the Profile holds lives in its own folder and data store.
public struct Profile: Hashable, Sendable, Identifiable {
    public let id: ProfileID
    public var name: String
    /// An emoji that marks the Profile in the sidebar.
    public var symbol: String
    /// The id of the Profile's Theme, picked from the Palette: it tints the sidebar and colours the Dock icon. Nil only for
    /// a Profile made before Themes existed.
    public var paletteID: String?

    public init(id: ProfileID, name: String, symbol: String = Profile.defaultSymbol, paletteID: String? = nil) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.paletteID = paletteID
    }

    public static let defaultSymbol = "👤"
}

/// The settings of one Profile, saved with it in its own database and never shared with another Profile.
public struct ProfileSettings: Hashable, Sendable {
    /// Nil until the user picks one: no search engine is ever preselected.
    public var searchEngine: SearchEngine?
    public var webContent: WebContentSettings

    public init(searchEngine: SearchEngine? = nil, webContent: WebContentSettings = WebContentSettings()) {
        self.searchEngine = searchEngine
        self.webContent = webContent
    }
}
