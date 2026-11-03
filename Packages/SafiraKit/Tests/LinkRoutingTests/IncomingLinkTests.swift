// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Testing

@Test(arguments: [
    ("https://example.com/", true),
    ("HTTP://example.com/", true),
    ("mailto:someone@example.com", false),
    ("slack://open", false),
])
func onlyHTTPAndHTTPSLinksAreWebLinks(address: String, isWebLink: Bool) throws {
    let link = IncomingLink(url: try #require(URL(string: address)), openerBundleIdentifier: "com.tinyspeck.slackmacgap")
    #expect(link.isWebLink == isWebLink)
}
