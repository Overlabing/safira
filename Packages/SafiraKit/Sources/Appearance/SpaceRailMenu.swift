// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DesignKit
import SafiraCore

/// What a secondary click on an item of the Space rail offers, as data: each command names the Space or Profile it acts
/// on, the clicked one whichever is current. A Space offers its own commands, then its Profile's; a Profile (a folded
/// dot, or a header in the "+n" panel) offers its own. The sections are separated by dividers.
public enum SpaceRailMenu {
    public enum Action: Hashable, Sendable {
        case editSpace(SpaceID)
        case moveSpaceLeft(SpaceID)
        case moveSpaceRight(SpaceID)
        case deleteSpace(SpaceID)
        case editProfile(ProfileID)
        case deleteProfile(ProfileID)
        case clearBrowsingData(ProfileID)
    }

    public struct Item: Hashable, Sendable {
        public let action: Action
        public let isEnabled: Bool

        public init(_ action: Action, isEnabled: Bool = true) {
            self.action = action
            self.isEnabled = isEnabled
        }
    }

    /// The menu of the Space `id` among the rail's `profiles`: Edit, Move Left and Right (not past the ends of its
    /// Profile), Delete (not its Profile's last Space), then its Profile's menu. Empty for a Space no Profile holds.
    public static func space(_ id: String, in profiles: [SpaceRailProfile]) -> [[Item]] {
        guard let space = SpaceID(uuidString: id),
              let owner = profiles.first(where: { $0.spaces.contains { $0.id == id } }) else { return [] }
        let spaces = owner.spaces.map(\.id)
        return [[
            Item(.editSpace(space)),
            Item(.moveSpaceLeft(space), isEnabled: spaces.first != id),
            Item(.moveSpaceRight(space), isEnabled: spaces.last != id),
            Item(.deleteSpace(space), isEnabled: spaces.count > 1),
        ]] + profile(owner.id, in: profiles)
    }

    /// The menu of the Profile `id`: Edit, Delete (not the last Profile), then Clear History and Website Data. Empty for
    /// a Profile the rail does not show.
    public static func profile(_ id: String, in profiles: [SpaceRailProfile]) -> [[Item]] {
        guard let profile = ProfileID(uuidString: id), profiles.contains(where: { $0.id == id }) else { return [] }
        return [
            [Item(.editProfile(profile)), Item(.deleteProfile(profile), isEnabled: profiles.count > 1)],
            [Item(.clearBrowsingData(profile))],
        ]
    }
}

extension SpaceRailMenu.Action {
    /// The Profile shown before the action runs, so that its result is visible: the Space's Profile, or the Profile
    /// itself. Nil for Delete Profile, whose result (the Profile leaving the rail) shows from any Profile, and showing it
    /// first would load its pages only to erase them; nil too for a Space no Profile of the rail holds.
    public func profileToShow(in profiles: [SpaceRailProfile]) -> ProfileID? {
        switch self {
        case .editSpace(let space), .moveSpaceLeft(let space), .moveSpaceRight(let space), .deleteSpace(let space):
            let key = space.rawValue.uuidString
            return profiles.first { $0.spaces.contains { $0.id == key } }.flatMap { ProfileID(uuidString: $0.id) }
        case .editProfile(let profile), .clearBrowsingData(let profile):
            return profile
        case .deleteProfile:
            return nil
        }
    }
}
