// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import Testing

/// A fresh Application Support folder for one test, removed when the test ends.
private final class TemporaryRoot {
    let layout = StoreLayout(root: FileManager.default.temporaryDirectory
        .appending(path: "safira-\(UUID().uuidString)", directoryHint: .isDirectory))

    deinit { try? FileManager.default.removeItem(at: layout.root) }
}

private let work = ProfileID(rawValue: UUID(uuidString: "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A")!)
private let personal = ProfileID(rawValue: UUID(uuidString: "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F")!)

/// #122: ⌘+, ⌘− and ⌘0 change the shown page's zoom, remembered per site in the Profile.
@MainActor
@Suite struct PageZoomTests {
    @Test func zoomingInStepsThePageAndTheBadgeFollows() {
        let fixture = SessionFixture()
        fixture.visit("https://news.example/today")
        #expect(fixture.session.selectedTab?.zoom == .actualSize)
        #expect(fixture.session.canResetZoom == false)

        fixture.session.zoomIn()
        fixture.session.zoomIn()

        #expect(fixture.selectedPage?.pageZoom == 1.25)
        #expect(fixture.session.selectedTab?.zoom.percentage == "125%")
        #expect(fixture.session.canResetZoom)

        fixture.session.zoomOut()
        #expect(fixture.selectedPage?.pageZoom == 1.15)
        fixture.session.resetZoom()
        #expect(fixture.selectedPage?.pageZoom == 1)
        #expect(fixture.session.siteZooms.all == [:])
    }

    @Test func theZoomStopsAtTheSmallestAndLargestSteps() {
        let fixture = SessionFixture()
        fixture.visit("https://news.example/")
        for _ in 0..<20 { fixture.session.zoomIn() }
        #expect(fixture.selectedPage?.pageZoom == 3)
        #expect(fixture.session.canZoomIn == false)
        for _ in 0..<20 { fixture.session.zoomOut() }
        #expect(fixture.selectedPage?.pageZoom == 0.5)
        #expect(fixture.session.canZoomOut == false)
    }

    @Test func aBlankTabHasNothingToZoom() {
        let fixture = SessionFixture()
        fixture.session.openNewTab()
        #expect(fixture.session.canZoomIn == false)
        fixture.session.zoomIn()
        #expect(fixture.session.siteZooms.all == [:])
    }

    @Test func theSiteKeepsItsZoomAcrossItsPagesAndAnotherSiteHasItsOwn() throws {
        let fixture = SessionFixture()
        let tab = fixture.visit("https://news.example/today")
        fixture.session.zoomIn()
        let page = try #require(fixture.pages[tab])

        page.followLink(to: URL(string: "https://news.example/tomorrow")!)
        #expect(page.pageZoom == 1.15)

        page.followLink(to: URL(string: "https://shop.example/")!)
        #expect(page.pageZoom == 1)
        #expect(fixture.session.selectedTab?.zoom == .actualSize)

        page.goBack()
        #expect(page.pageZoom == 1.15)
    }

    @Test func everyOpenPageOfTheSiteFollowsAndANewOneStartsAtIt() throws {
        let fixture = SessionFixture()
        let first = fixture.visit("https://news.example/a")
        let other = fixture.visit("https://shop.example/")
        let second = fixture.visit("https://news.example/b")

        fixture.session.zoomOut()

        #expect(fixture.pages[first]?.pageZoom == 0.85)
        #expect(fixture.pages[second]?.pageZoom == 0.85)
        #expect(fixture.pages[other]?.pageZoom == 1)
        let third = fixture.visit("https://NEWS.example/c")
        #expect(fixture.pages[third]?.pageZoom == 0.85)
    }

    @Test func aZoomIsKeptWithTheProfileAndNeverReachesAnotherProfile() throws {
        let root = TemporaryRoot()
        do {
            let database = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
            let fixture = SessionFixture(id: work, siteZooms: SiteZooms(database: database))
            fixture.visit("https://news.example/")
            fixture.session.zoomIn()
        }

        let relaunched = SiteZooms(database: try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work)))
        #expect(relaunched.all == [ZoomSite(host: "news.example")!: PageZoom(factor: 1.15)])
        let restored = SessionFixture(id: work, siteZooms: relaunched)
        restored.visit("https://news.example/later")
        #expect(restored.selectedPage?.pageZoom == 1.15)

        let other = SiteZooms(database: try ProfileDatabase(file: root.layout.profileDatabaseFile(for: personal)))
        #expect(other.all == [:])
        let elsewhere = SessionFixture(id: personal, siteZooms: other)
        elsewhere.visit("https://news.example/")
        #expect(elsewhere.selectedPage?.pageZoom == 1)
    }

    @Test func actualSizeForgetsTheSite() throws {
        let root = TemporaryRoot()
        let database = try ProfileDatabase(file: root.layout.profileDatabaseFile(for: work))
        let fixture = SessionFixture(id: work, siteZooms: SiteZooms(database: database))
        fixture.visit("https://news.example/")
        fixture.session.zoomIn()
        fixture.session.resetZoom()
        #expect(try database.siteZooms() == [:])
    }
}
