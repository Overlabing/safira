// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// The search engines a Profile can choose from, in the order they are offered. None is preselected.
public enum SearchEngine: String, CaseIterable, Sendable, Codable {
    case duckDuckGo
    case kagi
    case braveSearch
    case google
    case ecosia

    public var name: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .kagi: "Kagi"
        case .braveSearch: "Brave Search"
        case .google: "Google"
        case .ecosia: "Ecosia"
        }
    }

    public func searchURL(for query: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        // URLComponents leaves "+", "&" and "=" alone in query values; search engines read "+" as a space.
        let encoded = query.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) ?? query
        components.percentEncodedQuery = "q=\(encoded)"
        guard let url = components.url else { preconditionFailure("A search URL is always well formed") }
        return url
    }

    private var host: String {
        switch self {
        case .duckDuckGo: "duckduckgo.com"
        case .kagi: "kagi.com"
        case .braveSearch: "search.brave.com"
        case .google: "www.google.com"
        case .ecosia: "www.ecosia.org"
        }
    }

    private var path: String {
        switch self {
        case .duckDuckGo: "/"
        case .kagi, .braveSearch, .google, .ecosia: "/search"
        }
    }

    private static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=#?/"))
}

extension SearchEngine {
    /// The entry for the search engine: every Profile needs one, and none is chosen for the user.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "search.engine",
                title: "Search engine",
                value: "Chosen by you",
                explanation: "Each Profile has its own search engine, and none is chosen for you. A Profile cannot be "
                    + "created without one; if you skip it, the Command bar asks at the first search.",
                whereToChange: "Defaults window",
                control: .choice
            ),
        ]
    }
}
