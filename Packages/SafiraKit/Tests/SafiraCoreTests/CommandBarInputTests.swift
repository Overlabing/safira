// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

private func resolved(_ text: String) -> String? {
    switch CommandBarInput(text) {
    case .address(let url, _): "address \(url.absoluteString)"
    case .search(let query): "search \(query)"
    case nil: nil
    }
}

@Test(arguments: [
    ("example.com", "address https://example.com"),
    ("  example.com/path?q=1#top  ", "address https://example.com/path?q=1#top"),
    ("sub.example.co.uk", "address https://sub.example.co.uk"),
    ("xn--p1ai.xn--p1ai", "address https://xn--p1ai.xn--p1ai"),
    ("localhost:8080/admin", "address https://localhost:8080/admin"),
    ("192.168.1.1", "address https://192.168.1.1"),
    ("http://example.com/", "address http://example.com/"),
    ("https://example.com/a%20b", "address https://example.com/a%20b"),
])
func anAddressOpensWithHTTPSUnlessTypedWithAScheme(text: String, expected: String) {
    #expect(resolved(text) == expected)
}

@Test(arguments: [
    ("swift testing", "search swift testing"),
    ("swift", "search swift"),
    ("3.14", "search 3.14"),
    ("999.1.1.1", "search 999.1.1.1"),
    ("user@example.com", "search user@example.com"),
    ("example.com is down", "search example.com is down"),
    ("example.", "search example."),
    ("-bad.com", "search -bad.com"),
    ("localhost:http", "search localhost:http"),
    ("ftp://example.com", "search ftp://example.com"),
    ("about:blank", "search about:blank"),
])
func anythingElseIsASearch(text: String, expected: String) {
    #expect(resolved(text) == expected)
}

@Test func blankTextOpensNothing() {
    #expect(resolved("") == nil)
    #expect(resolved("   \n") == nil)
}

@Test(arguments: [
    ("example.com", true),
    ("localhost:8080/admin", true),
    ("192.168.1.1", true),
    ("https://example.com", false),
    ("http://example.com", false),
])
func onlyAnAddressTypedWithoutASchemeIsOpenedHTTPSFirst(text: String, httpsFirst: Bool) {
    guard case .address(_, let scheme)? = CommandBarInput(text) else {
        Issue.record("\(text) was not read as an address")
        return
    }
    #expect((scheme == .defaultedToHTTPS) == httpsFirst)
}
