// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Testing

private let slack = Opener(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack")

@Test(arguments: [
    ("https://example.com/", true),
    ("HTTP://example.com/", true),
    ("mailto:someone@example.com", false),
    ("slack://open", false),
    ("file:///Users/someone/page.html", false),
])
func onlyHTTPAndHTTPSLinksAreWebLinks(address: String, isWebLink: Bool) throws {
    let link = IncomingLink(url: try #require(URL(string: address)), opener: slack)
    #expect(link.isWebLink == isWebLink)
}

@Test(arguments: [
    ("https://example.com/", true),
    ("file:///Users/someone/page.html", true),
    ("mailto:someone@example.com", false),
    ("slack://open", false),
])
func safiraOpensWebLinksAndLocalFilesOnly(address: String, isOpenable: Bool) throws {
    #expect(IncomingLink(url: try #require(URL(string: address))).isOpenable == isOpenable)
}

@Test func aWebLinkIsNamedByItsHostAndALocalFileByItsFileName() throws {
    let web = IncomingLink(url: try #require(URL(string: "https://docs.example.com:8443/guide?x=1#top")))
    let file = IncomingLink(url: URL(filePath: "/Users/someone/Documents/report.html"))

    #expect(web.title == "docs.example.com")
    #expect(web.detail == "https://docs.example.com:8443/guide?x=1#top")
    #expect(file.title == "report.html")
    #expect(file.detail == "/Users/someone/Documents/report.html")
}
