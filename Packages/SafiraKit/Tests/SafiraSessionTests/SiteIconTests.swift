// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CoreGraphics
import Foundation
import ImageIO
import SafiraCore
import SafiraSession
import Testing
import UniformTypeIdentifiers

/// A square PNG of `side` pixels: its width tells which candidate an icon came from.
func pngData(side: Int) -> Data {
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

/// A folder of site icons for one test, removed when the test ends.
final class TemporaryIconFolder {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "safira-icons-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit { try? FileManager.default.removeItem(at: url) }

    var fileNames: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []).sorted()
    }
}

private func url(_ text: String) -> URL { URL(string: text)! }

/// Site icons: what a loaded page's links lead to, what is cached per Profile, and that nothing else fetches.
@MainActor
struct SiteIconTests {
    @Test func aLoadedPageGetsTheLargestUsableIconOfItsSiteAndNothingFromAnotherSite() async throws {
        let fixture = SessionFixture()
        fixture.preparePage = { page in
            page.siteResources = [
                url("https://static.example.com/touch.png"): .unusable,
                url("https://www.example.com/f32.png"): .resource(pngData(side: 32), cacheControl: "max-age=600"),
                url("https://www.example.com/f16.png"): .resource(pngData(side: 16), cacheControl: nil),
            ]
        }
        fixture.visit("https://www.example.com/news")
        let page = try #require(fixture.selectedPage)

        page.finishLoading(links: [
            ["rel": "icon", "href": "/f16.png", "sizes": "16x16"],
            ["rel": "icon", "href": "f32.png", "sizes": "32x32"],
            ["rel": "apple-touch-icon", "href": "https://static.example.com/touch.png", "sizes": "180x180"],
            ["rel": "icon", "href": "https://cdn.tracker.net/icon.png", "sizes": "512x512"],
            ["rel": "stylesheet", "href": "/site.css"],
        ], base: url("https://www.example.com/"))
        await fixture.session.siteIcons.settled()

        #expect(page.fetched.map(\.absoluteString) == [
            "https://static.example.com/touch.png", "https://www.example.com/f32.png",
        ])
        #expect(fixture.session.siteIcons.icon(for: url("https://www.example.com/other"))?.width == 32)
        #expect(fixture.session.siteIcons.icon(for: url("https://example.com/"))?.width == nil,
                "another origin is another key")
    }

    @Test func aPageWithNoIconLinksTriesTheDefaultPathsOfItsOrigin() async throws {
        let fixture = SessionFixture()
        fixture.preparePage = { page in
            page.siteResources = [url("https://a.example:8443/favicon.ico"): .resource(pngData(side: 24), cacheControl: nil)]
        }
        fixture.visit("https://a.example:8443/")
        let page = try #require(fixture.selectedPage)

        page.finishLoading(links: [])
        await fixture.session.siteIcons.settled()

        #expect(page.fetched.map(\.absoluteString) == [
            "https://a.example:8443/apple-touch-icon.png", "https://a.example:8443/favicon.ico",
        ])
        #expect(fixture.session.siteIcons.icon(for: url("https://a.example:8443/x"))?.width == 24)
    }

    @Test func manifestIconsComeFirst() async throws {
        let manifest = #"{"icons": [{"src": "icons/192.png", "sizes": "192x192", "type": "image/png"}]}"#
        let fixture = SessionFixture()
        fixture.preparePage = { page in
            page.siteResources = [
                url("https://app.example/app.webmanifest"): .resource(Data(manifest.utf8), cacheControl: nil),
                url("https://app.example/icons/192.png"): .resource(pngData(side: 40), cacheControl: nil),
            ]
        }
        fixture.visit("https://app.example/")
        let page = try #require(fixture.selectedPage)

        page.finishLoading(links: [
            ["rel": "manifest", "href": "/app.webmanifest"],
            ["rel": "icon", "href": "/favicon.png"],
        ])
        await fixture.session.siteIcons.settled()

        #expect(page.fetched.map(\.absoluteString) == [
            "https://app.example/app.webmanifest", "https://app.example/icons/192.png",
        ])
        #expect(fixture.session.siteIcons.icon(for: url("https://app.example/"))?.width == 40)
    }

    @Test func aManifestLinkThatDeclaresItsTypeStillGivesItsIcons() async throws {
        let manifest = #"{"icons": [{"src": "/icons/512.png", "sizes": "512x512", "type": "image/png"}]}"#
        let fixture = SessionFixture()
        fixture.preparePage = { page in
            page.siteResources = [
                url("https://typed.example/app.webmanifest"): .resource(Data(manifest.utf8), cacheControl: nil),
                url("https://typed.example/icons/512.png"): .resource(pngData(side: 48), cacheControl: nil),
                url("https://typed.example/favicon-16.png"): .resource(pngData(side: 16), cacheControl: nil),
            ]
        }
        fixture.visit("https://typed.example/")
        let page = try #require(fixture.selectedPage)

        page.finishLoading(links: [
            ["rel": "manifest", "href": "/app.webmanifest", "type": "application/manifest+json"],
            ["rel": "icon", "href": "/favicon-16.png", "sizes": "16x16"],
        ])
        await fixture.session.siteIcons.settled()

        #expect(page.fetched.map(\.absoluteString) == [
            "https://typed.example/app.webmanifest", "https://typed.example/icons/512.png",
        ])
        #expect(fixture.session.siteIcons.icon(for: url("https://typed.example/"))?.width == 48)
    }

    /// An SVG icon with a style sheet: the kit's decoder refuses it, so the next candidate is used.
    private static let styledSVG = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16"><style>rect { fill: red; }</style>\
        <rect width="16" height="16"/></svg>
        """.utf8)

    @Test func aRefusedSVGIconFallsThroughToTheNextCandidate() async throws {
        let fixture = SessionFixture()
        fixture.preparePage = { page in
            page.siteResources = [
                url("https://vector.example/icon.svg"): .resource(Self.styledSVG, cacheControl: nil),
                url("https://vector.example/favicon-24.png"): .resource(pngData(side: 24), cacheControl: nil),
            ]
        }
        fixture.visit("https://vector.example/")
        let page = try #require(fixture.selectedPage)

        page.finishLoading(links: [
            ["rel": "icon", "href": "/icon.svg", "sizes": "any", "type": "image/svg+xml"],
            ["rel": "icon", "href": "/favicon-24.png", "sizes": "24x24"],
        ])
        await fixture.session.siteIcons.settled()

        #expect(page.fetched.map(\.absoluteString) == [
            "https://vector.example/icon.svg", "https://vector.example/favicon-24.png",
        ])
        #expect(fixture.session.siteIcons.icon(for: url("https://vector.example/"))?.width == 24)
    }

    @Test func aRefusedSVGIconAloneLeavesTheLetterTile() async throws {
        let folder = TemporaryIconFolder()
        let fixture = SessionFixture(siteIcons: ProfileSiteIcons(directory: folder.url))
        fixture.preparePage = { page in
            page.siteResources = [url("https://vector.example/icon.svg"): .resource(Self.styledSVG, cacheControl: nil)]
        }
        fixture.visit("https://vector.example/")
        let page = try #require(fixture.selectedPage)

        page.finishLoading(links: [["rel": "icon", "href": "/icon.svg", "type": "image/svg+xml"]])
        await fixture.session.siteIcons.settled()

        #expect(page.fetched.map(\.path) == ["/icon.svg", "/apple-touch-icon.png", "/favicon.ico"])
        #expect(fixture.session.siteIcons.icon(for: url("https://vector.example/")) == nil)
        #expect(folder.fileNames == ["https%3A%2F%2Fvector.example.none"])
    }

    @Test func noFetchHappensForAPageThatIsNotLoaded() async throws {
        let folder = TemporaryIconFolder()
        let fixture = SessionFixture(siteIcons: ProfileSiteIcons(directory: folder.url))
        let selected = TabID()
        fixture.session.restore(SavedSession(tabs: [
            TabRecord(id: TabID(), address: url("https://dormant.example/"), title: "Dormant"),
            TabRecord(id: selected, address: url("https://shown.example/"), title: "Shown"),
        ], selectedTabID: selected))
        let icons = fixture.session.siteIcons

        // What the sidebar and the Command bar do for a dormant Tab and a history suggestion: look the icon up.
        #expect(icons.icon(for: url("https://dormant.example/")) == nil)
        #expect(icons.icon(for: url("https://history.example/visited")) == nil)
        await icons.settled()

        #expect(fixture.createdPageCount == 1, "the dormant Tab has no page")
        #expect(fixture.pages.values.flatMap(\.fetched) == [])
        #expect(folder.fileNames == [])

        // The shown Tab's page loads: it fetches for its own site only.
        fixture.selectedPage?.finishLoading(links: [])
        await icons.settled()
        #expect(fixture.pages.values.flatMap(\.fetched).map { $0.host() } == ["shown.example", "shown.example"])
    }

    @Test func aPageThatIsNotHTTPSIsNeverFetchedForAndKeepsItsLetterTile() async throws {
        let fixture = SessionFixture()
        fixture.visit("http://plain.example/")
        let page = try #require(fixture.selectedPage)

        page.finishLoading(links: [["rel": "icon", "href": "https://plain.example/favicon.png"]])
        await fixture.session.siteIcons.settled()

        #expect(page.fetched == [])
        #expect(fixture.session.siteIcons.icon(for: url("http://plain.example/")) == nil)
    }

    @Test func aSiteWithNoUsableIconKeepsTheLetterTileAndIsNotAskedAgainSoon() async throws {
        let folder = TemporaryIconFolder()
        let fixture = SessionFixture(siteIcons: ProfileSiteIcons(directory: folder.url))
        fixture.preparePage = { page in
            page.siteResources = [url("https://bare.example/favicon.ico"): .resource(Data("not an image".utf8), cacheControl: nil)]
        }
        fixture.visit("https://bare.example/")
        let page = try #require(fixture.selectedPage)

        page.finishLoading(links: [])
        await fixture.session.siteIcons.settled()
        page.followLink(to: url("https://bare.example/next"))
        page.finishLoading(links: [])
        await fixture.session.siteIcons.settled()

        #expect(fixture.session.siteIcons.icon(for: url("https://bare.example/")) == nil)
        #expect(page.fetched.count == 2, "the default paths once, not again on the next page")
        #expect(folder.fileNames == ["https%3A%2F%2Fbare.example.none"])
    }

    @Test func aSiteThatDidNotAnswerIsAskedAgainOnTheNextLoad() async throws {
        let fixture = SessionFixture()
        fixture.preparePage = { page in
            page.siteResources = [
                url("https://flaky.example/apple-touch-icon.png"): .failed,
                url("https://flaky.example/favicon.ico"): .failed,
            ]
        }
        fixture.visit("https://flaky.example/")
        let page = try #require(fixture.selectedPage)

        page.finishLoading(links: [])
        await fixture.session.siteIcons.settled()
        page.finishLoading(links: [])
        await fixture.session.siteIcons.settled()

        #expect(page.fetched.count == 4)
    }

    @Test func aFreshIconIsNotFetchedAgainAndADormantTabShowsItAfterARelaunch() async throws {
        let folder = TemporaryIconFolder()
        let before = SessionFixture(siteIcons: ProfileSiteIcons(directory: folder.url))
        before.preparePage = { page in
            page.siteResources = [url("https://kept.example/favicon.ico"): .resource(pngData(side: 32), cacheControl: nil)]
        }
        before.visit("https://kept.example/")
        let page = try #require(before.selectedPage)
        page.finishLoading(links: [])
        await before.session.siteIcons.settled()
        page.finishLoading(links: [])
        await before.session.siteIcons.settled()
        #expect(page.fetched.count == 2, "the default paths once")
        #expect(folder.fileNames == ["https%3A%2F%2Fkept.example.expires", "https%3A%2F%2Fkept.example.png"])

        let after = SessionFixture(siteIcons: ProfileSiteIcons(directory: folder.url))
        let shown = TabID()
        after.session.restore(SavedSession(tabs: [
            TabRecord(id: TabID(), address: url("https://kept.example/page"), title: "Kept"),
            TabRecord(id: shown, address: url("about:blank")),
        ], selectedTabID: shown))
        let icons = after.session.siteIcons
        #expect(icons.icon(for: after.session.tabs[0].address) == nil, "read from disk, not at once")
        await icons.settled()

        #expect(icons.icon(for: after.session.tabs[0].address)?.width == 32)
        #expect(after.pages.values.flatMap(\.fetched) == [])
    }

    @Test func anIconsLifetimeIsKeptWithinSafirasBounds() {
        let day: TimeInterval = 86_400
        #expect(ProfileSiteIcons.lifetime.lifetime(cacheControl: "no-cache") == day)
        #expect(ProfileSiteIcons.lifetime.lifetime(cacheControl: "max-age=60") == day)
        #expect(ProfileSiteIcons.lifetime.lifetime(cacheControl: nil) == 7 * day)
        #expect(ProfileSiteIcons.lifetime.lifetime(cacheControl: "max-age=31536000") == 30 * day)
        #expect(ProfileSiteIcons.negativeLifetime == day)
    }

    @Test func theKeyIsThePagesOrigin() {
        #expect(ProfileSiteIcons.key(for: url("https://WWW.Example.com/a?b#c")) == "https://www.example.com")
        #expect(ProfileSiteIcons.key(for: url("https://example.com:443/")) == "https://example.com")
        #expect(ProfileSiteIcons.key(for: url("https://example.com:8443/")) == "https://example.com:8443")
        #expect(ProfileSiteIcons.key(for: url("http://example.com/")) == nil)
        #expect(ProfileSiteIcons.key(for: url("about:blank")) == nil)
        #expect(ProfileSiteIcons.key(for: nil) == nil)
    }

    @Test func clearingARangeRemovesTheIconsFetchedInItAndKeepsOlderOnes() async throws {
        let folder = TemporaryIconFolder()
        let fixture = SessionFixture(siteIcons: ProfileSiteIcons(directory: folder.url))
        fixture.preparePage = { page in
            page.siteResources = [
                url("https://old.example/favicon.ico"): .resource(pngData(side: 16), cacheControl: nil),
                url("https://new.example/favicon.ico"): .resource(pngData(side: 16), cacheControl: nil),
            ]
        }
        fixture.visit("https://old.example/")
        fixture.selectedPage?.finishLoading(links: [])
        fixture.visit("https://new.example/")
        fixture.selectedPage?.finishLoading(links: [])
        let icons = fixture.session.siteIcons
        await icons.settled()
        let twoDaysAgo = Date().addingTimeInterval(-2 * 86_400)
        for name in folder.fileNames where name.contains("old.example") {
            try FileManager.default.setAttributes([.modificationDate: twoDaysAgo],
                                                  ofItemAtPath: folder.url.appending(path: name).path(percentEncoded: false))
        }

        try await icons.clear(since: ClearRange.lastDay.start())
        #expect(icons.icon(for: url("https://new.example/")) == nil)
        #expect(icons.icon(for: url("https://old.example/")) == nil)
        await icons.settled()

        #expect(folder.fileNames == ["https%3A%2F%2Fold.example.expires", "https%3A%2F%2Fold.example.png"])
        #expect(icons.icon(for: url("https://old.example/"))?.width == 16)
        #expect(icons.icon(for: url("https://new.example/")) == nil)

        try await icons.clear(since: ClearRange.allTime.start())
        #expect(folder.fileNames == [])
    }
}
