// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

@MainActor
@Suite struct ExternalLinkTests {
    @Test func anExternalLinkOpensAsANewSelectedTabAndLoads() throws {
        let fixture = SessionFixture()
        fixture.session.openNewTab()

        let id = fixture.session.openExternalLink(try #require(URL(string: "https://example.com/a")))

        #expect(fixture.session.tabs.count == 2)
        #expect(fixture.session.selectedTabID == id)
        #expect(fixture.addresses == [nil, "https://example.com/a"])
        #expect(fixture.selectedPage?.loads.map(\.url.absoluteString) == ["https://example.com/a"])
        #expect(fixture.selectedPage?.loads.map(\.httpsFirst) == [false])
    }

    @Test func anExternalLinkOpensInTheLastActiveSpaceNotTheFirstOne() throws {
        let fixture = SessionFixture()
        let second = fixture.session.createSpace(name: "Reading", emoji: "📚")
        fixture.session.selectSpace(fixture.session.spaces[0].id)
        fixture.session.selectSpace(second)

        fixture.session.openExternalLink(try #require(URL(string: "https://example.com/")))

        #expect(fixture.session.spaces[0].tabs.isEmpty)
        #expect(fixture.session.spaces[1].tabs.map { $0.address?.absoluteString } == ["https://example.com/"])
        #expect(fixture.session.activeSpaceID == second)
    }

    @Test func aLocalFileOpensLikeAnyOtherAddress() {
        let fixture = SessionFixture()

        fixture.session.openExternalLink(URL(filePath: "/Users/someone/page.html"))

        #expect(fixture.addresses == ["file:///Users/someone/page.html"])
    }
}
