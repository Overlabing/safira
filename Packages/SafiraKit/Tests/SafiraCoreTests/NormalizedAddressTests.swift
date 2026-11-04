// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

private func normalized(_ address: String) -> String? {
    URL(string: address).flatMap(NormalizedAddress.init)?.value
}

@Suite struct NormalizedAddressTests {
    @Test(arguments: [
        ("HTTPS://Example.COM/Path", "https://example.com/Path"),
        ("https://EXAMPLE.com", "https://example.com"),
        ("https://example.com/", "https://example.com"),
        ("https://example.com", "https://example.com"),
        ("https://example.com/docs/", "https://example.com/docs"),
        ("https://example.com/docs/?page=2", "https://example.com/docs?page=2"),
        ("https://example.com/docs#intro", "https://example.com/docs"),
        ("https://example.com/#/inbox", "https://example.com"),
        ("https://example.com/docs/#intro", "https://example.com/docs"),
        ("https://example.com/a?utm_source=news&utm_medium=mail", "https://example.com/a"),
        ("https://example.com/a?utm_source=news&page=2&utm_campaign=x", "https://example.com/a?page=2"),
        ("https://example.com/a?UTM_Source=news&Page=2", "https://example.com/a?Page=2"),
        ("https://example.com/a?fbclid=IwAR0&q=swift", "https://example.com/a?q=swift"),
        ("https://example.com/a?q=swift&gclid=Cj0K", "https://example.com/a?q=swift"),
        ("https://example.com/a?mc_eid=1234&mc_cid=5678", "https://example.com/a"),
        ("https://example.com/a?b=2&a=1&c=3", "https://example.com/a?b=2&a=1&c=3"),
        ("https://example.com/a?ref=home&source=nav", "https://example.com/a?ref=home&source=nav"),
        ("https://example.com/a?q=a%20b&utm_term=a%20b", "https://example.com/a?q=a%20b"),
        ("https://example.com/a?flag&utm_source=x", "https://example.com/a?flag"),
        ("https://example.com/a?q=1&&", "https://example.com/a?q=1"),
        ("https://example.com/a?utm_source=x#top", "https://example.com/a"),
        ("http://example.com/a", "http://example.com/a"),
        ("https://user@example.com:8443/a/", "https://user@example.com:8443/a"),
        ("https://sub.Example.com/A/B", "https://sub.example.com/A/B"),
    ] as [(String, String)])
    func normalizes(address: String, expected: String) {
        #expect(normalized(address) == expected)
    }

    @Test(arguments: [
        ("https://Example.com/a/?utm_source=x&b=1#frag", "https://example.com/a?b=1"),
        ("https://example.com/a", "https://example.com/a/"),
    ] as [(String, String)])
    func addressesThatDifferOnlyInIgnoredPartsAreEqual(first: String, second: String) {
        #expect(normalized(first) == normalized(second))
    }

    @Test(arguments: [
        ("https://example.com/a", "http://example.com/a"),
        ("https://example.com/a", "https://example.com/A"),
        ("https://example.com/a?b=1&c=2", "https://example.com/a?c=2&b=1"),
        ("https://example.com/a?b=1", "https://example.com/a?b=2"),
        ("https://example.com/a", "https://www.example.com/a"),
        ("https://example.com/a", "https://example.com:8443/a"),
    ] as [(String, String)])
    func addressesThatDifferInAnythingElseAreNotEqual(first: String, second: String) {
        #expect(normalized(first) != normalized(second))
    }

    @Test(arguments: ["mailto:someone@example.com", "file:///tmp/page.html", "slack://open", "about:blank", "https:///path"])
    func anAddressThatIsNotAWebAddressHasNoNormalizedForm(address: String) {
        #expect(normalized(address) == nil)
    }

    @Test(arguments: [
        "utm_source", "utm_medium", "UTM_CAMPAIGN", "utm_anything", "fbclid", "gclid", "dclid", "gbraid", "wbraid",
        "msclkid", "twclid", "yclid", "ttclid", "igshid", "li_fat_id", "mc_eid", "mc_cid", "_hsenc", "_hsmi", "mkt_tok",
        "srsltid", "_ga", "_gl",
    ])
    func knownTrackingParametersAreRecognized(name: String) {
        #expect(TrackingParameters.isTracking(name))
    }

    @Test(arguments: ["q", "page", "ref", "source", "utm", "id", "v", "t", "fbclid2"])
    func otherParametersAreNotTracking(name: String) {
        #expect(!TrackingParameters.isTracking(name))
    }

    @Test func theSavedTabOfTheActiveSpaceIsFoundBeforeOneOfAnotherSpace() throws {
        let profile = ProfileID(rawValue: UUID())
        let home = SpaceRecord(id: SpaceID(), name: "Home", emoji: "🏠", tabs: [
            TabRecord(id: TabID(), address: URL(string: "https://example.com/a")),
        ])
        let work = SpaceRecord(id: SpaceID(), name: "Work", emoji: "💼", tabs: [
            TabRecord(id: TabID(), address: URL(string: "https://example.com/b")),
            TabRecord(id: TabID(), address: URL(string: "https://EXAMPLE.com/a/#x")),
        ])
        let saved = SavedSession(spaces: [home, work], activeSpaceID: work.id)
        let address = try #require(NormalizedAddress(URL(string: "https://example.com/a?utm_source=x")!))

        #expect(saved.matchingTab(for: address, in: profile) == MatchingTab(profile: profile, space: work.id, tab: work.tabs[1].id))
        #expect(SavedSession(spaces: [home], activeSpaceID: home.id).matchingTab(for: address, in: profile)
            == MatchingTab(profile: profile, space: home.id, tab: home.tabs[0].id))
        #expect(SavedSession().matchingTab(for: address, in: profile) == nil)
    }

    @Test func aSavedPinnedTabOrOneInsideAFolderIsFoundToo() throws {
        let profile = ProfileID(rawValue: UUID())
        let pinned = TabRecord(id: TabID(), address: URL(string: "https://example.com/pinned"))
        let inFolder = TabRecord(id: TabID(), address: URL(string: "https://example.com/folder"))
        let inSubFolder = TabRecord(id: TabID(), address: URL(string: "https://example.com/sub"))
        let home = SpaceRecord(id: SpaceID(), name: "Home", emoji: "🏠", pinned: [
            .tab(pinned),
            .folder(FolderRecord(id: FolderID(), name: "Docs", isExpanded: false, items: [
                .tab(inFolder),
                .folder(FolderRecord(id: FolderID(), name: "More", isExpanded: false, items: [.tab(inSubFolder)])),
            ])),
        ], tabs: [TabRecord(id: TabID(), address: URL(string: "https://example.com/plain"))])
        let saved = SavedSession(spaces: [home], activeSpaceID: home.id)

        func found(_ link: String) throws -> TabID? {
            let address = try #require(NormalizedAddress(URL(string: link)!))
            return saved.matchingTab(for: address, in: profile)?.tab
        }

        #expect(try found("https://example.com/pinned?utm_source=x") == pinned.id)
        #expect(try found("https://example.com/folder#top") == inFolder.id)
        #expect(try found("https://EXAMPLE.com/sub/") == inSubFolder.id)
        #expect(try found("https://example.com/plain") == home.tabs[0].id)
    }
}
