// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import DesignKit
import Foundation
import SafiraCore
import Testing

/// The Space rail's menu per item: every command acts on the Space or Profile that was clicked, not the current one.
struct SpaceRailMenuTests {
    private static func id(_ n: Int) -> UUID { UUID(uuidString: "00000000-0000-0000-0000-00000000000\(n)")! }

    private let home = SpaceSummary(id: SpaceID(rawValue: id(1)), name: "Home", emoji: "🏠")
    private let reading = SpaceSummary(id: SpaceID(rawValue: id(2)), name: "Reading", emoji: "📚")
    private let ops = SpaceSummary(id: SpaceID(rawValue: id(3)), name: "Ops", emoji: "🚀")
    private let family = SpaceSummary(id: SpaceID(rawValue: id(4)), name: "Family", emoji: "🏡")

    private let work = Profile(id: ProfileID(rawValue: id(5)), name: "Work", symbol: "💼")
    private let personal = Profile(id: ProfileID(rawValue: id(6)), name: "Personal", symbol: "🏡")

    /// Work is the Active profile on Home; Personal, folded, has one Space.
    private var rail: [SpaceRailProfile] {
        SpaceRailContent.profiles([work, personal], activeID: work.id, spaces: { id in
            id == work.id ? ProfileSpaces(spaces: [home, reading, ops], lastSpaceID: home.id)
                          : ProfileSpaces(spaces: [family], lastSpaceID: family.id)
        }, shortcuts: SpaceRailContent.Shortcuts())
    }

    private func key(_ space: SpaceSummary) -> String { space.id.rawValue.uuidString }
    private func key(_ profile: Profile) -> String { profile.id.rawValue.uuidString }

    @Test func aSpaceThatIsNotCurrentGetsItsOwnCommandsThenItsProfiles() {
        let menu = SpaceRailMenu.space(key(reading), in: rail)

        #expect(menu == [
            [.init(.editSpace(reading.id)), .init(.moveSpaceLeft(reading.id)), .init(.moveSpaceRight(reading.id)),
             .init(.deleteSpace(reading.id))],
            [.init(.editProfile(work.id)), .init(.deleteProfile(work.id))],
            [.init(.clearBrowsingData(work.id))],
        ])
    }

    @Test func aSpaceCannotMovePastTheEndsOfItsProfile() {
        let first = SpaceRailMenu.space(key(home), in: rail)[0]
        let last = SpaceRailMenu.space(key(ops), in: rail)[0]

        #expect(first.map(\.isEnabled) == [true, false, true, true])
        #expect(last.map(\.isEnabled) == [true, true, false, true])
    }

    /// From the "+n" panel: a Space of the folded Profile acts on that Space and on that Profile.
    @Test func aSpaceOfAnotherProfileActsOnItAndOnItsProfile() {
        let menu = SpaceRailMenu.space(key(family), in: rail)

        #expect(menu == [
            [.init(.editSpace(family.id)), .init(.moveSpaceLeft(family.id), isEnabled: false),
             .init(.moveSpaceRight(family.id), isEnabled: false), .init(.deleteSpace(family.id), isEnabled: false)],
            [.init(.editProfile(personal.id)), .init(.deleteProfile(personal.id))],
            [.init(.clearBrowsingData(personal.id))],
        ])
    }

    @Test func aFoldedProfileGetsItsOwnCommands() {
        let menu = SpaceRailMenu.profile(key(personal), in: rail)

        #expect(menu == [
            [.init(.editProfile(personal.id)), .init(.deleteProfile(personal.id))],
            [.init(.clearBrowsingData(personal.id))],
        ])
    }

    @Test func theLastProfileCannotBeDeletedFromItsMenu() {
        let alone = SpaceRailContent.profiles([work], activeID: work.id, spaces: { _ in
            ProfileSpaces(spaces: [home], lastSpaceID: home.id)
        }, shortcuts: SpaceRailContent.Shortcuts())

        #expect(SpaceRailMenu.profile(key(work), in: alone)[0].map(\.isEnabled) == [true, false])
        #expect(SpaceRailMenu.space(key(home), in: alone).map { $0.map(\.isEnabled) }
            == [[true, false, false, false], [true, false], [true]])
    }

    @Test func anUnknownItemHasNoMenu() {
        #expect(SpaceRailMenu.space(UUID().uuidString, in: rail).isEmpty)
        #expect(SpaceRailMenu.profile("not-a-profile", in: rail).isEmpty)
    }
}
