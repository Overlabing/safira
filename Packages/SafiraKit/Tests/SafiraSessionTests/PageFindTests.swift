// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

private let article = URL(string: "https://news.example/article")!

/// #122: ⌘F finds in the shown page, with the highlighted match's place among the matches; ⌘G and ⇧⌘G go round them.
@MainActor
@Suite struct PageFindTests {
    private func fixture(text: String = "Swift is fast. SWIFT is safe. swift is fun.") -> SessionFixture {
        let fixture = SessionFixture()
        fixture.preparePage = { $0.texts[article] = text }
        fixture.visit(article.absoluteString)
        return fixture
    }

    @Test func typingHighlightsTheFirstMatchAndCountsThemAll() async {
        let fixture = fixture()
        let find = fixture.session.find
        await find.show()
        #expect(find.isShown)
        #expect(find.result == .empty)

        await find.search("swift")

        #expect(find.result == .match(current: 1, count: 3))
        #expect(fixture.selectedPage?.finds.last?.text == "swift")
        #expect(fixture.selectedPage?.isHighlighting == true)
    }

    @Test func nextAndPreviousGoRoundTheMatches() async {
        let fixture = fixture()
        let find = fixture.session.find
        await find.show()
        await find.search("swift")

        await find.next()
        #expect(find.result == .match(current: 2, count: 3))
        await find.next()
        await find.next()
        #expect(find.result == .match(current: 1, count: 3))
        await find.previous()
        #expect(find.result == .match(current: 3, count: 3))
        #expect(fixture.selectedPage?.finds.last?.backwards == true)
    }

    @Test func aTextThePageLacksFindsNothing() async {
        let fixture = fixture()
        let find = fixture.session.find
        await find.show()
        await find.search("kotlin")
        #expect(find.result == .notFound)
        await find.search("")
        #expect(find.result == .empty)
    }

    @Test func closingTakesTheHighlightAwayAndKeepsTheTextForFindNext() async {
        let fixture = fixture()
        let find = fixture.session.find
        await find.show()
        await find.search("safe")
        find.close()

        #expect(!find.isShown)
        #expect(fixture.selectedPage?.isHighlighting == false)
        #expect(find.text == "safe")

        await find.next()
        #expect(find.isShown)
        #expect(find.result == .match(current: 1, count: 1))
    }

    @Test func aMatchTheVisibleTextDoesNotShowHasNoCount() async {
        let fixture = fixture()
        fixture.selectedPage?.countOverride = 0
        let find = fixture.session.find
        await find.show()
        await find.search("in a field")
        #expect(find.result == .uncounted)
        await find.next()
        #expect(find.result == .uncounted)
    }

    @Test func anotherTabIsSearchedFromTheTop() async {
        let fixture = fixture()
        let find = fixture.session.find
        await find.show()
        await find.search("swift")
        await find.next()
        let first = fixture.session.selectedTabID
        fixture.visit("https://other.example/")
        fixture.selectedPage?.texts[URL(string: "https://other.example/")!] = "swift"
        fixture.selectedPage?.reload()

        await find.next()

        #expect(find.result == .match(current: 1, count: 1))
        #expect(first != fixture.session.selectedTabID)
    }
}
