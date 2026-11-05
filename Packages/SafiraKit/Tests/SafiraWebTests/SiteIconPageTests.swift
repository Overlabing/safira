// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraWeb
import Testing
import WebKit

/// A real page's side of site icons: the links it reads after a load, out of the page's reach, and the fetches it makes
/// through its own Profile's data store, which carry that Profile's cookies and no other's.
@MainActor
@Suite(.serialized) struct SiteIconPageTests {
    @Test func aLoadedPageReportsItsLinksAsSafirasOwnScriptReadsThem() async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let page = context.makePage(for: TabID())
            var reported: PageIconLinks?
            page.onIconLinks = { reported = $0 }
            // The page's own scripts cannot change what Safira's content world reads.
            let html = """
                <html><head><base href="https://127.0.0.1:9/sub/">
                <link rel="icon" href="a.png" sizes="32x32">
                <link rel="Apple-Touch-Icon" href="/touch.png" data-ignored="yes">
                <link rel="manifest" href="app.webmanifest" type="application/manifest+json">
                <link rel="mask-icon" href="mask.svg" color="#123456">
                <link rel="stylesheet" href="site.css">
                <script>Element.prototype.getAttribute = () => "https://evil.example/x.png"; Array.from = () => [];</script>
                </head><body>page</body></html>
                """
            page.webView.loadHTMLString(html, baseURL: URL(string: "https://127.0.0.1:9/page"))
            try await waitUntil("the page reports its links") { reported != nil }

            let links = try #require(reported)
            #expect(links.page.absoluteString == "https://127.0.0.1:9/page")
            #expect(links.base.absoluteString == "https://127.0.0.1:9/sub/")
            #expect(links.tags == [
                ["rel": "icon", "href": "a.png", "sizes": "32x32"],
                ["rel": "Apple-Touch-Icon", "href": "/touch.png"],
                ["rel": "manifest", "href": "app.webmanifest", "type": "application/manifest+json"],
                ["rel": "mask-icon", "href": "mask.svg", "color": "#123456"],
                ["rel": "stylesheet", "href": "site.css"],
            ])
            page.close()
        }
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aPageFetchesThroughItsOwnProfilesDataStoreAndListsNoDownload() async throws {
        let server = try await RoutedPageServer.start([
            "/page": .html("page"),
            "/icon.png": RoutedPageServer.Page(body: "icon-bytes"),
            "/big.png": RoutedPageServer.Page(body: String(repeating: "x", count: 4_096)),
        ])
        let work = ProfileID(rawValue: UUID())
        let personal = ProfileID(rawValue: UUID())
        do {
            let workContext = ProfileWebContext(profileID: work)
            let personalContext = ProfileWebContext(profileID: personal)
            let cookie = try #require(HTTPCookie(properties: [
                .name: "session", .value: "work-only", .domain: "127.0.0.1", .path: "/",
            ]))
            await workContext.dataStore.httpCookieStore.setCookie(cookie)
            let workPage = workContext.makePage(for: TabID())
            let personalPage = personalContext.makePage(for: TabID())
            for page in [workPage, personalPage] {
                page.load(server.url("/page"), httpsFirst: false)
                try await waitUntil("the page loads") { page.webView.url == server.url("/page") && !page.webView.isLoading }
            }

            let fromWork = await workPage.fetchSiteResource(server.url("/icon.png"), byteLimit: 1_024)
            let fromPersonal = await personalPage.fetchSiteResource(server.url("/icon.png"), byteLimit: 1_024)

            #expect(fromWork == .resource(Data("icon-bytes".utf8), cacheControl: "no-store"))
            #expect(fromPersonal == .resource(Data("icon-bytes".utf8), cacheControl: "no-store"))
            let iconRequests = server.requests.filter { $0.hasPrefix("GET /icon.png ") }
            #expect(iconRequests.count == 2)
            #expect(iconRequests.first?.lowercased().contains("cookie: session=work-only\n") == true)
            #expect(iconRequests.last?.lowercased().contains("cookie:") == false)
            #expect(await workPage.fetchSiteResource(server.url("/missing.png"), byteLimit: 1_024) == .unusable)
            #expect(await workPage.fetchSiteResource(server.url("/big.png"), byteLimit: 1_024) == .unusable)
            #expect(workContext.downloads.all.isEmpty)
            #expect(personalContext.downloads.all.isEmpty)

            let closedPort = try await LocalServer.closedPort()
            let unreachable = URL(string: "http://127.0.0.1:\(closedPort)/icon.png")!
            #expect(await workPage.fetchSiteResource(unreachable, byteLimit: 1_024) == .failed)
            workPage.close()
            #expect(await workPage.fetchSiteResource(server.url("/icon.png"), byteLimit: 1_024) == .failed)
            personalPage.close()
        }
        server.stop()
        await removeDataStoreWhenReleased(work)
        await removeDataStoreWhenReleased(personal)
    }
}
