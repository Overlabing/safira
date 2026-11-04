// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkPickerUI
import LinkRouting
import SafiraCore
import Testing

private let work = Profile(id: ProfileID(uuidString: "00000001-0000-4000-8000-000000000000")!, name: "Work", symbol: "💼")
private let home = Profile(id: ProfileID(uuidString: "00000002-0000-4000-8000-000000000000")!, name: "Home", symbol: "🏡")

@MainActor
@Suite struct AlwaysChoiceTests {
    private func picker(_ address: String = "https://Shop.Example/cart") -> LinkPickerModel<ProfileID> {
        LinkPickerModel(link: IncomingLink(url: URL(string: address)!), profiles: [work, home])
    }

    @Test func alwaysIsOffWhenThePickerOpensAndTheHostIsTheLowercaseSite() {
        let model = picker()
        #expect(!model.remembers)
        #expect(model.rememberedHost == "shop.example")
    }

    @Test func theAKeyTurnsAlwaysOnAndOffWithoutChoosingOrHighlightingARow() {
        let model = picker()

        #expect(model.handle(.character("a")) == .none)
        #expect(model.remembers)
        #expect(model.highlightedIndex == nil)
        #expect(model.handle(.character("A")) == .none)
        #expect(!model.remembers)
    }

    @Test func aNumberKeyStillChoosesImmediatelyAndAlwaysStaysAsSet() {
        let model = picker()
        _ = model.handle(.character("a"))

        #expect(model.handle(.character("2")) == .chose(home.id))
        #expect(model.remembers)
    }

    @Test func aLinkWithNoSiteOffersNoAlways() {
        let model = picker("file:///tmp/page.html")
        #expect(model.rememberedHost == nil)

        _ = model.handle(.character("a"))
        model.setRemembers(true)

        #expect(!model.remembers)
    }

    @Test func theSpaceStepOpensWithAlwaysAsTheProfileStepLeftIt() {
        let spaces = [SpaceChoice(id: SpaceID(), name: "Dev", emoji: "🛠"), SpaceChoice(id: SpaceID(), name: "Docs", emoji: "📄")]
        let link = IncomingLink(url: URL(string: "https://shop.example/")!)

        #expect(LinkPickerModel(link: link, spaces: spaces, remembers: true).remembers)
        #expect(!LinkPickerModel(link: link, spaces: spaces).remembers)
        #expect(!LinkPickerModel(link: IncomingLink(url: URL(string: "file:///tmp/a.html")!), spaces: spaces, remembers: true).remembers)
    }

    @Test(arguments: [(Character("a"), true), (Character("A"), true), (Character("1"), false), (Character("b"), false)])
    func onlyAAndShiftATurnAlwaysOn(key: Character, toggles: Bool) {
        #expect(LinkPickerKey.togglesRemembering(key) == toggles)
    }
}
