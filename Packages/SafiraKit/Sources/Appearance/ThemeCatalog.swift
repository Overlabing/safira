// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import ColorCore

/// The Palette Safira offers and how a saved Theme id finds its Theme again. Profiles and Spaces store only the id, and
/// the ids are ThemeKit's own, so a Palette that grows never invalidates what is saved.
public enum ThemeCatalog {
    public static let palette = Palette.standard

    /// The ids of the Palette in the order the pickers offer them.
    public static var ids: [String] { palette.themes.map(\.id) }

    /// The Theme behind a saved id; nil for no id or an id this Palette does not know.
    public static func theme(id: String?) -> Theme? {
        id.flatMap(palette.theme(id:))
    }

    /// The Theme of a saved id, or `fallback` when there is none.
    public static func theme(id: String?, fallback: Theme) -> Theme {
        theme(id: id) ?? fallback
    }

    /// The first Theme of the Palette, used when nothing else decides.
    public static var first: Theme { palette.themes[0] }

    /// The id a new Profile or Space starts with: the first Theme of the Palette none of `taken` uses, so that the ones
    /// side by side differ; once every Theme is used, the least used one, earliest first.
    public static func nextID(avoiding taken: [String?]) -> String {
        let counts = Dictionary(grouping: taken.compactMap { $0 }, by: { $0 }).mapValues(\.count)
        return palette.themes.min { (counts[$0.id] ?? 0) < (counts[$1.id] ?? 0) }?.id ?? first.id
    }
}
