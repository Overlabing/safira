// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import Testing

private let workID = ProfileID(rawValue: UUID(uuidString: "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A")!)
private let personalID = ProfileID(rawValue: UUID(uuidString: "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F")!)

@MainActor
private func described(_ suggestions: [CommandBarSuggestion]) -> [String] {
    suggestions.map { suggestion in
        switch suggestion.kind {
        case .openTab: "tab: \(suggestion.title)"
        case .history: "history: \(suggestion.title)"
        }
    }
}

@MainActor
private func fixtureWithHistory(id: ProfileID = workID) throws -> SessionFixture {
    SessionFixture(searchEngine: .duckDuckGo, id: id, history: try ProfileDatabase.inMemory())
}

/// The Command bar's jump to a Tab and its local suggestions, through the Profile session.
@MainActor
@Suite struct SuggestionTests {
    @Test func partOfATabsTitleSuggestsThatTab() async throws {
        let fixture = try fixtureWithHistory()
        fixture.visit("https://github.com/Overlabing/safira", titled: "Overlabing/safira: a native browser")
        fixture.visit("https://swift.org", titled: "Swift.org")

        let suggestions = await fixture.session.suggestions(for: "native brow")

        #expect(described(suggestions) == ["tab: Overlabing/safira: a native browser"])
        #expect(suggestions.first?.address.absoluteString == "https://github.com/Overlabing/safira")
        #expect(suggestions.first?.spaceEmoji == "🏠")
    }

    @Test func openingTheSuggestionOfATabJumpsToItWithoutLoadingAnything() async throws {
        let fixture = try fixtureWithHistory()
        let docs = fixture.visit("https://docs.example.com/", titled: "Reference Manual")
        fixture.visit("https://news.example.com/", titled: "Morning News")
        let loadsBefore = fixture.pages.values.map(\.loadCount).reduce(0, +)

        fixture.session.openCommandBar(for: .newTab)
        let suggestions = await fixture.session.suggestions(for: "manual")
        fixture.session.openSuggestion(try #require(suggestions.first))

        #expect(fixture.session.selectedTabID == docs)
        #expect(fixture.session.commandBarTarget == nil)
        #expect(fixture.session.tabs.count == 2)
        #expect(fixture.pages.values.map(\.loadCount).reduce(0, +) == loadsBefore)
    }

    @Test func aTabInAnotherSpaceOfTheProfileIsSuggestedAndShownWithItsSpace() async throws {
        let fixture = try fixtureWithHistory()
        let home = fixture.session.activeSpaceID
        let recipe = fixture.visit("https://cook.example/", titled: "Tarte tatin")
        let reading = fixture.session.createSpace(name: "Reading", emoji: "📚")
        fixture.visit("https://read.example/", titled: "Tarte au citron")

        let suggestions = await fixture.session.suggestions(for: "tarte")

        #expect(described(suggestions) == ["tab: Tarte au citron", "tab: Tarte tatin"])
        #expect(suggestions.map(\.spaceEmoji) == ["📚", "🏠"])
        fixture.session.openSuggestion(suggestions[1])
        #expect(fixture.session.selectedTabID == recipe)
        #expect(fixture.session.activeSpaceID == home)
        #expect(fixture.session.spaces.first { $0.id == reading }?.tabs.count == 1)
    }

    @Test func tabsAreMatchedWithAccentsAndLetterCaseIgnored() async throws {
        let fixture = try fixtureWithHistory()
        fixture.visit("https://cafe.example/", titled: "Le Café de la Gare")

        #expect(described(await fixture.session.suggestions(for: "CAFE")) == ["tab: Le Café de la Gare"])
        #expect(described(await fixture.session.suggestions(for: "gare café")) == ["tab: Le Café de la Gare"])
        #expect(described(await fixture.session.suggestions(for: "CAFÉ")) == ["tab: Le Café de la Gare"])
    }

    @Test func aTabWithoutATitleIsFoundByItsAddress() async throws {
        let fixture = try fixtureWithHistory()
        fixture.visit("https://status.example.org/incidents")

        let suggestions = await fixture.session.suggestions(for: "incidents")

        #expect(described(suggestions) == ["tab: https://status.example.org/incidents"])
    }

    @Test func aRestoredDormantTabIsSuggestedWithoutCreatingItsPage() async throws {
        let fixture = try fixtureWithHistory()
        let space = SpaceID()
        fixture.session.restore(SavedSession(spaces: [
            SpaceRecord(id: space, name: "Home", emoji: "🏠", tabs: [
                TabRecord(id: TabID(), address: URL(string: "https://a.example/")!, title: "Alpha"),
                TabRecord(id: TabID(), address: URL(string: "https://b.example/")!, title: "Beta Release Notes"),
            ])
        ], activeSpaceID: space))
        let pagesBefore = fixture.createdPageCount

        let suggestions = await fixture.session.suggestions(for: "release")

        #expect(described(suggestions) == ["tab: Beta Release Notes"])
        #expect(fixture.createdPageCount == pagesBefore)
    }

    @Test func historySuggestsPagesNoLongerOpenMostRecentFirst() async throws {
        let fixture = try fixtureWithHistory()
        let first = fixture.visit("https://blog.example/old", titled: "Swift blog: old post")
        fixture.visit("https://blog.example/new", titled: "Swift blog: new post")
        fixture.session.close(first)
        fixture.session.closeSelectedTab()

        let suggestions = await fixture.session.suggestions(for: "swift")

        #expect(described(suggestions) == ["history: Swift blog: new post", "history: Swift blog: old post"])
        #expect(suggestions.map(\.address.absoluteString) == ["https://blog.example/new", "https://blog.example/old"])
    }

    @Test func aPageThatIsOpenIsListedAsItsTabAndNotAgainFromHistory() async throws {
        let fixture = try fixtureWithHistory()
        fixture.visit("https://open.example/", titled: "Shared page")
        let closed = fixture.visit("https://closed.example/", titled: "Shared page elsewhere")
        fixture.session.close(closed)

        let suggestions = await fixture.session.suggestions(for: "shared")

        #expect(described(suggestions) == ["tab: Shared page", "history: Shared page elsewhere"])
    }

    @Test func historyIsSearchedWithAccentsAndLetterCaseIgnored() async throws {
        let fixture = try fixtureWithHistory()
        let tab = fixture.visit("https://musee.example/", titled: "Musée d’Orsay")
        fixture.session.close(tab)

        #expect(described(await fixture.session.suggestions(for: "musee")) == ["history: Musée d’Orsay"])
        #expect(described(await fixture.session.suggestions(for: "ORSAY")) == ["history: Musée d’Orsay"])
        #expect(described(await fixture.session.suggestions(for: "MUSÉE")) == ["history: Musée d’Orsay"])
    }

    @Test func openingAHistorySuggestionLoadsItWhereTheCommandBarTargets() async throws {
        let fixture = try fixtureWithHistory()
        let old = fixture.visit("https://archive.example/post", titled: "Archived post")
        fixture.session.close(old)
        let other = fixture.visit("https://other.example/", titled: "Other")

        fixture.session.openCommandBar(for: .newTab)
        let suggestion = try #require(await fixture.session.suggestions(for: "archived").first)
        fixture.session.openSuggestion(suggestion)

        #expect(fixture.session.tabs.count == 2)
        #expect(fixture.session.selectedTab?.address?.absoluteString == "https://archive.example/post")
        #expect(fixture.session.tabs.first?.id == other)

        fixture.session.openCommandBar(for: .selectedTab)
        let again = try #require(await fixture.session.suggestions(for: "other").first)
        fixture.session.openSuggestion(again)
        #expect(fixture.session.selectedTabID == other)
    }

    @Test func typingNothingSuggestsNothing() async throws {
        let fixture = try fixtureWithHistory()
        fixture.visit("https://a.example/", titled: "A")

        #expect(await fixture.session.suggestions(for: "").isEmpty)
        #expect(await fixture.session.suggestions(for: "  \n ").isEmpty)
    }

    @Test func theNumberOfSuggestionsIsLimitedAndTabsComeBeforeHistory() async throws {
        let fixture = try fixtureWithHistory()
        for number in 1...4 {
            fixture.session.close(fixture.visit("https://h.example/\(number)", titled: "Item \(number)"))
        }
        fixture.visit("https://t.example/1", titled: "Item open one")
        fixture.visit("https://t.example/2", titled: "Item open two")

        let suggestions = await fixture.session.suggestions(for: "item", limit: 4)

        #expect(described(suggestions) == ["tab: Item open one", "tab: Item open two", "history: Item 4", "history: Item 3"])
    }

    @Test func aSessionWithoutHistorySuggestsOnlyItsTabs() async throws {
        let fixture = SessionFixture()
        let gone = fixture.visit("https://gone.example/", titled: "Gone page")
        fixture.session.close(gone)
        fixture.visit("https://here.example/", titled: "Here page")

        #expect(described(await fixture.session.suggestions(for: "page")) == ["tab: Here page"])
    }
}

/// What the Active profile's suggestions never include.
@MainActor
@Suite struct SuggestionScopeTests {
    @Test func aProfilesSuggestionsComeFromItsOwnTabsAndHistoryOnly() async throws {
        let work = try fixtureWithHistory(id: workID)
        let personal = try fixtureWithHistory(id: personalID)
        work.session.close(work.visit("https://wiki.work.example/", titled: "Quarterly plan (history)"))
        work.visit("https://tracker.work.example/", titled: "Quarterly tracker")
        personal.session.close(personal.visit("https://recipes.example/", titled: "Quarterly budget recipes (history)"))
        personal.visit("https://bank.example/", titled: "Quarterly statement")

        #expect(described(await work.session.suggestions(for: "quarterly"))
            == ["tab: Quarterly tracker", "history: Quarterly plan (history)"])
        #expect(described(await personal.session.suggestions(for: "quarterly"))
            == ["tab: Quarterly statement", "history: Quarterly budget recipes (history)"])
    }

    @Test func aSuggestionOfOneProfileCannotOpenATabInAnother() async throws {
        let work = try fixtureWithHistory(id: workID)
        let personal = try fixtureWithHistory(id: personalID)
        let secret = work.visit("https://wiki.work.example/", titled: "Salary review")
        let tabs = personal.session.tabs.count

        let suggestion = try #require(await work.session.suggestions(for: "salary").first)
        personal.session.openSuggestion(suggestion)

        #expect(suggestion.kind == .openTab(secret))
        #expect(personal.session.tabs.count == tabs)
        #expect(personal.session.selectedTabID == nil)
    }

    @Test func aProfileWithNoSharedHistoryFindsNothingOfAnothers() async throws {
        let work = try fixtureWithHistory(id: workID)
        let personal = try fixtureWithHistory(id: personalID)
        work.session.close(work.visit("https://wiki.work.example/", titled: "Salary review"))

        #expect(await personal.session.suggestions(for: "salary").isEmpty)
    }
}

/// How pages enter history (decision D1) and that typing never touches the network.
@MainActor
@Suite struct HistoryRecordingTests {
    @Test func aVisitIsRecordedWithItsTitleOnceThePageHasLoaded() async throws {
        let fixture = try fixtureWithHistory()
        let tab = fixture.visit("https://slow.example/")
        let page = try #require(fixture.pages[tab])
        page.setLoading(true)
        page.setTitle("Half loaded")

        #expect(fixture.session.tabs.count == 1)
        fixture.session.close(tab)
        #expect(described(await fixture.session.suggestions(for: "half")).isEmpty)
        #expect(described(await fixture.session.suggestions(for: "slow.example")) == ["history: https://slow.example/"])

        let reopened = fixture.visit("https://slow.example/two")
        let second = try #require(fixture.pages[reopened])
        second.setLoading(true)
        second.setTitle("Almost")
        second.setLoading(false)
        fixture.session.close(reopened)

        #expect(described(await fixture.session.suggestions(for: "almost")) == ["history: Almost"])
    }

    @Test func aTitleThatChangesLaterReplacesTheOldOne() async throws {
        let fixture = try fixtureWithHistory()
        let tab = fixture.visit("https://spa.example/", titled: "Inbox")
        fixture.pages[tab]?.setTitle("Inbox (3)")
        fixture.session.close(tab)

        #expect(described(await fixture.session.suggestions(for: "inbox")) == ["history: Inbox (3)"])
    }

    @Test func aPageWithAPasswordFieldEntersHistoryByAddressOnly() async throws {
        let fixture = try fixtureWithHistory()
        let tab = fixture.visit("https://bank.example/login")
        fixture.pages[tab]?.showPasswordField()
        fixture.pages[tab]?.setTitle("Sign in to Contoso Vault")
        fixture.session.close(tab)

        #expect(described(await fixture.session.suggestions(for: "contoso")).isEmpty)
        #expect(described(await fixture.session.suggestions(for: "bank.example/login")) == ["history: https://bank.example/login"])
    }

    @Test func aPageReachedByAPostEntersHistoryByAddressOnly() async throws {
        let fixture = try fixtureWithHistory()
        let tab = fixture.visit("https://shop.example/cart", titled: "Cart")
        fixture.pages[tab]?.submitPostForm(to: URL(string: "https://shop.example/order/4521")!)
        fixture.pages[tab]?.setTitle("Order 4521 for Jane Doe")
        fixture.session.close(tab)

        #expect(described(await fixture.session.suggestions(for: "jane")).isEmpty)
        #expect(described(await fixture.session.suggestions(for: "order/4521")) == ["history: https://shop.example/order/4521"])
        #expect(described(await fixture.session.suggestions(for: "cart")) == ["history: Cart"])
    }

    @Test func aLinkFollowedInATabIsAnotherVisitButAReloadIsNot() async throws {
        let fixture = try fixtureWithHistory()
        let tab = fixture.visit("https://site.example/a", titled: "Page A")
        fixture.pages[tab]?.followLink(to: URL(string: "https://site.example/b")!)
        fixture.pages[tab]?.setTitle("Page B")
        fixture.session.reload()
        fixture.session.close(tab)

        #expect(described(await fixture.session.suggestions(for: "page")) == ["history: Page B", "history: Page A"])
    }

    @Test func bringingARestoredTabBackIsNotAVisitButNavigatingFromItIs() async throws {
        let database = try ProfileDatabase.inMemory()
        let fixture = SessionFixture(history: database)
        let space = SpaceID()
        let tab = TabID()
        fixture.session.restore(SavedSession(spaces: [
            SpaceRecord(id: space, name: "Home", emoji: "🏠",
                        tabs: [TabRecord(id: tab, address: URL(string: "https://back.example/")!, title: "Back")],
                        selectedTabID: tab)
        ], activeSpaceID: space))
        fixture.pages[tab]?.setTitle("Back")
        await fixture.session.recordedHistorySettled()

        #expect(try await database.searchHistory("back.example", limit: 5).isEmpty)

        fixture.pages[tab]?.followLink(to: URL(string: "https://back.example/next")!)
        await fixture.session.recordedHistorySettled()

        #expect(try await database.searchHistory("back.example", limit: 5).map(\.url.absoluteString) == ["https://back.example/next"])
    }

    @Test func addressesThatAreNotWebPagesAreNotHistory() async throws {
        let database = try ProfileDatabase.inMemory()
        let fixture = SessionFixture(history: database)
        let tab = fixture.visit("https://start.example/", titled: "Start")
        fixture.pages[tab]?.followLink(to: URL(string: "about:blank")!)
        fixture.pages[tab]?.followLink(to: URL(string: "file:///tmp/notes.txt")!)
        await fixture.session.recordedHistorySettled()

        #expect(try await database.searchHistory("blank notes tmp", limit: 5).isEmpty)
        #expect(try await database.searchHistory("start", limit: 5).count == 1)
    }

    @Test func typingStartsNoPageLoadAndCreatesNoPage() async throws {
        let fixture = try fixtureWithHistory()
        fixture.session.close(fixture.visit("https://closed.example/", titled: "Closed one"))
        fixture.visit("https://open.example/", titled: "Open one")
        fixture.session.openCommandBar(for: .newTab)
        let pages = fixture.createdPageCount
        let loads = fixture.pages.values.map(\.loadCount).reduce(0, +)
        let restores = fixture.pages.values.map(\.restoreCount).reduce(0, +)

        for typed in ["o", "op", "ope", "open", "open on", "open one", "closed", "swift testing", "example.com"] {
            _ = await fixture.session.suggestions(for: typed)
        }

        #expect(fixture.createdPageCount == pages)
        #expect(fixture.pages.values.map(\.loadCount).reduce(0, +) == loads)
        #expect(fixture.pages.values.map(\.restoreCount).reduce(0, +) == restores)
        #expect(fixture.session.tabs.count == 1)
        #expect(fixture.session.commandBarTarget == .newTab)
    }
}

@Suite struct SuggestionHighlightTests {
    @Test func aSearchHighlightsTheFirstSuggestion() {
        #expect(SuggestionHighlight(typing: "manual", count: 3).index == 0)
        #expect(SuggestionHighlight(typing: "swift testing", count: 1).index == 0)
    }

    @Test func nothingIsHighlightedWithoutSuggestionsOrForTypedAddresses() {
        #expect(SuggestionHighlight(typing: "manual", count: 0).index == nil)
        #expect(SuggestionHighlight(typing: "github.com", count: 2).index == nil)
        #expect(SuggestionHighlight(typing: "https://example.org/path", count: 2).index == nil)
    }

    @Test func downGoesThroughTheSuggestionsThenBackToTheTypedText() {
        var highlight = SuggestionHighlight(typing: "github.com", count: 2)
        highlight.moveDown(count: 2)
        #expect(highlight.index == 0)
        highlight.moveDown(count: 2)
        #expect(highlight.index == 1)
        highlight.moveDown(count: 2)
        #expect(highlight.index == nil)
    }

    @Test func upGoesFromTheTypedTextToTheLastSuggestionAndBack() {
        var highlight = SuggestionHighlight(typing: "github.com", count: 3)
        highlight.moveUp(count: 3)
        #expect(highlight.index == 2)
        highlight.moveUp(count: 3)
        highlight.moveUp(count: 3)
        #expect(highlight.index == 0)
        highlight.moveUp(count: 3)
        #expect(highlight.index == nil)
    }

    @Test func movingWithNoSuggestionsHighlightsNothing() {
        var highlight = SuggestionHighlight(typing: "x", count: 0)
        highlight.moveDown(count: 0)
        highlight.moveUp(count: 0)
        #expect(highlight.index == nil)
    }
}

@Suite struct SuggestionTextTests {
    @Test func foldingIgnoresLetterCaseAndAccents() {
        #expect(SuggestionText.folded("Éléphant ÇA Noël") == "elephant ca noel")
    }

    @Test func everyWordMustAppearInAnyField() {
        #expect(SuggestionText.matches("hub safira", in: ["Overlabing/safira", "https://github.com/x"]))
        #expect(!SuggestionText.matches("hub gitlab", in: ["Overlabing/safira", "https://github.com/x"]))
        #expect(!SuggestionText.matches("   ", in: ["anything"]))
    }
}
