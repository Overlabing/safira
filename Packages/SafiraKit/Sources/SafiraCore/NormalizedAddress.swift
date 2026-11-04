// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// The query parameters that only say where a visitor came from. A link and an open Tab differing in these alone are
/// the same page.
public enum TrackingParameters {
    public static let prefixes = ["utm_"]

    public static let names: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "twclid", "yclid", "ttclid", "igshid", "li_fat_id",
        "mc_eid", "mc_cid", "_hsenc", "_hsmi", "mkt_tok", "srsltid", "_ga", "_gl",
    ]

    /// Parameter names compare without letter case and with their percent-encoding undone.
    public static func isTracking(_ name: String) -> Bool {
        let name = (name.removingPercentEncoding ?? name).lowercased()
        return names.contains(name) || prefixes.contains { name.hasPrefix($0) }
    }
}

/// The form of a web address used to compare a link with open Tabs: scheme and host without letter case, no trailing
/// slash, no fragment, no tracking parameter. Every other part, the order of the remaining parameters included, is kept.
public struct NormalizedAddress: Hashable, Sendable, CustomStringConvertible {
    public let value: String

    public var description: String { value }

    /// Nil for an address that is not an http or https address with a host.
    public init?(_ url: URL) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.percentEncodedHost?.lowercased(), !host.isEmpty else { return nil }
        components.scheme = scheme
        components.percentEncodedHost = host
        components.fragment = nil
        var path = components.percentEncodedPath
        if path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path
        let kept = components.percentEncodedQuery?
            .split(separator: "&", omittingEmptySubsequences: true)
            .filter { !TrackingParameters.isTracking(String($0.prefix { $0 != "=" })) }
        components.percentEncodedQuery = kept?.isEmpty == false ? kept?.joined(separator: "&") : nil
        guard let string = components.string else { return nil }
        value = string
    }
}

/// A Tab that shows the address of an incoming link, with the Space and the Profile that hold it.
public struct MatchingTab: Hashable, Sendable {
    public let profile: ProfileID
    public let space: SpaceID
    public let tab: TabID

    public init(profile: ProfileID, space: SpaceID, tab: TabID) {
        self.profile = profile
        self.space = space
        self.tab = tab
    }
}

extension SavedSession {
    /// The saved Tab of this Profile, pinned or not, whose last address is `address`: the active Space is searched
    /// first, then the others in sidebar order.
    public func matchingTab(for address: NormalizedAddress, in profile: ProfileID) -> MatchingTab? {
        let active = activeSpace
        let ordered = (active.map { [$0] } ?? []) + spaces.filter { $0.id != active?.id }
        for space in ordered {
            if let tab = space.allTabs.first(where: { $0.address.flatMap(NormalizedAddress.init) == address }) {
                return MatchingTab(profile: profile, space: space.id, tab: tab.id)
            }
        }
        return nil
    }
}
