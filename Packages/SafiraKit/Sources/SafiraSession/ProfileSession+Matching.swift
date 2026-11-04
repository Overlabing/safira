// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// What the Main window offers after a link was answered by a Matching tab instead of a new Tab.
public struct MatchBanner: Hashable, Identifiable, Sendable {
    public let id = UUID()
    /// The Matching tab, which is the Tab shown while the banner is.
    public let tab: TabID
    /// The link that arrived, with its fragment and tracking parameters as they were sent.
    public let link: URL
}

/// A source of Tabs that an incoming link may match.
@MainActor
public protocol MatchingTabSearchable: AnyObject {
    func matchingTab(for address: NormalizedAddress) -> MatchingTab?
}

extension ProfileSession {
    /// The Tab, in any Space, whose current address has the same Normalized address, a Pinned tab or one inside a
    /// Folder included, collapsed or not. A Tab not loaded since launch counts by its last saved address. The active
    /// Space is searched first.
    public func matchingTab(for address: NormalizedAddress) -> MatchingTab? {
        for space in [activeSpace] + spaces.filter({ $0.id != activeSpaceID }) {
            if let tab = space.allTabs.first(where: { $0.address.flatMap(NormalizedAddress.init) == address }) {
                return MatchingTab(profile: profileID, space: space.id, tab: tab.id)
            }
        }
        return nil
    }

    /// Shows a Matching tab, switching to its Space, and raises the banner that offers to open `link` in a new Tab.
    /// False, and nothing changes, when the Tab is gone or belongs to another Profile.
    @discardableResult
    public func focus(_ match: MatchingTab, openedFrom link: URL) -> Bool {
        guard match.profile == profileID, allTabs.contains(where: { $0.id == match.tab }) else { return false }
        select(match.tab)
        matchBanner = MatchBanner(tab: match.tab, link: link)
        return true
    }

    /// The banner's action: opens the link as a new Tab, selected, in the active Space, and takes the banner down.
    @discardableResult
    public func openMatchBannerLinkInNewTab() -> TabID? {
        guard let banner = matchBanner else { return nil }
        matchBanner = nil
        return openExternalLink(banner.link)
    }

    public func dismissMatchBanner() {
        matchBanner = nil
    }

    /// The banner belongs to the Matching tab it came with: showing any other Tab takes it down.
    func dropStaleMatchBanner() {
        if matchBanner?.tab != selectedTabID { matchBanner = nil }
    }
}
