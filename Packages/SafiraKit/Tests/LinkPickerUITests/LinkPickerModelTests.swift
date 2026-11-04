// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkPickerUI
import LinkRouting
import SafiraCore
import Testing

private func profile(_ n: Int, _ name: String, _ symbol: String) -> Profile {
    Profile(id: ProfileID(uuidString: String(format: "%08d-0000-4000-8000-000000000000", n))!, name: name, symbol: symbol)
}

private let work = profile(1, "Work", "💼")
private let home = profile(2, "Home", "🏡")
private let school = profile(3, "School", "🎓")

@MainActor
private func picker(_ profiles: [Profile] = [work, home, school]) -> LinkPickerModel {
    LinkPickerModel(link: IncomingLink(url: URL(string: "https://example.com/a")!,
                                       opener: Opener(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack")),
                    profiles: profiles)
}

@MainActor
@Suite struct LinkPickerModelTests {
    @Test func theRowsFollowTheSidebarOrderAndAreNumberedFromOne() {
        let model = picker()

        #expect(model.rows.map(\.number) == [1, 2, 3])
        #expect(model.rows.map(\.name) == ["Work", "Home", "School"])
        #expect(model.rows.map(\.symbol) == ["💼", "🏡", "🎓"])
        #expect(model.title == "example.com")
        #expect(model.openerName == "Slack")
    }

    @Test func nothingIsHighlightedWhenThePickerOpens() {
        #expect(picker().highlightedIndex == nil)
    }

    @Test func returnDoesNothingUntilARowIsHighlighted() {
        let model = picker()

        #expect(model.handle(.return) == .none)
        #expect(model.handle(.return) == .none)
        #expect(model.highlightedIndex == nil)
    }

    @Test(arguments: [("1", 0), ("2", 1), ("3", 2)] as [(Character, Int)])
    func aNumberKeyChoosesItsProfileAtOnce(key: Character, index: Int) {
        let model = picker()

        #expect(model.handle(.character(key)) == .chose(model.rows[index].id))
    }

    @Test(arguments: ["0", "4", "9", "a", " "] as [Character])
    func aKeyThatMatchesNoRowChoosesNothing(key: Character) {
        let model = picker()

        #expect(model.handle(.character(key)) == .none)
        #expect(model.highlightedIndex == nil)
    }

    @Test func downThenReturnChoosesTheFirstProfile() {
        let model = picker()

        #expect(model.handle(.down) == .none)
        #expect(model.highlightedIndex == 0)
        #expect(model.handle(.return) == .chose(work.id))
    }

    @Test func upThenReturnChoosesTheLastProfile() {
        let model = picker()

        #expect(model.handle(.up) == .none)
        #expect(model.highlightedIndex == 2)
        #expect(model.handle(.return) == .chose(school.id))
    }

    @Test func arrowsMoveTheHighlightAndWrapAroundTheEnds() {
        let model = picker()

        _ = model.handle(.right)
        _ = model.handle(.right)
        #expect(model.highlightedIndex == 1)
        _ = model.handle(.down)
        _ = model.handle(.down)
        #expect(model.highlightedIndex == 0)
        _ = model.handle(.left)
        #expect(model.highlightedIndex == 2)
        _ = model.handle(.up)
        #expect(model.highlightedIndex == 1)
        #expect(model.handle(.return) == .chose(home.id))
    }

    @Test func escapeDismissesTheLinkWhetherOrNotARowIsHighlighted() {
        let model = picker()
        #expect(model.handle(.escape) == .cancelled)

        _ = model.handle(.down)
        #expect(model.handle(.escape) == .cancelled)
    }

    @Test func clickingARowChoosesIt() {
        let model = picker()

        #expect(model.choose(home.id) == .chose(home.id))
        #expect(model.choose(profile(9, "Gone", "👻").id) == .none)
    }

    @Test func onlyTheFirstNineProfilesHaveANumberKeyButAllCanBeReachedWithTheArrows() {
        let many = (1...11).map { profile($0, "P\($0)", "🔹") }
        let model = picker(many)

        #expect(model.rows.map(\.numberKey) == ["1", "2", "3", "4", "5", "6", "7", "8", "9", nil, nil])
        #expect(model.handle(.character("9")) == .chose(many[8].id))
        let arrows = picker(many)
        for _ in 0..<11 { _ = arrows.handle(.down) }
        #expect(arrows.highlightedIndex == 10)
        #expect(arrows.handle(.return) == .chose(many[10].id))
    }
}
