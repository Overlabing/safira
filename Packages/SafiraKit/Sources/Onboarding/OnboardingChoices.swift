// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import SafiraCore

/// What the user picks during onboarding, written all at once when they finish. Nothing is preselected: the search
/// engine and the Shortcut preset start empty.
public struct OnboardingChoices: Hashable, Sendable {
    public var profileName: String
    public var profileSymbol: String
    public var searchEngine: SearchEngine?
    public var shortcutPreset: ShortcutPreset?
    /// The position of every switch of the defaults summary, by entry identifier.
    public var toggles: [String: Bool]

    public init(profileName: String = "", profileSymbol: String = Profile.defaultSymbol, searchEngine: SearchEngine? = nil,
                shortcutPreset: ShortcutPreset? = nil, toggles: [String: Bool] = [:]) {
        self.profileName = profileName
        self.profileSymbol = profileSymbol
        self.searchEngine = searchEngine
        self.shortcutPreset = shortcutPreset
        self.toggles = toggles
    }

    /// A Profile needs a name and a search engine.
    public var isComplete: Bool {
        !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && searchEngine != nil
    }
}
