// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

private func site(_ address: String) -> String? {
    RegistrableDomain(URL(string: address))?.value
}

@Suite struct RegistrableDomainTests {
    @Test(arguments: [
        ("https://google.com/", "google.com"),
        ("https://mail.google.com/mail/u/0", "google.com"),
        ("http://WWW.Example.COM:8080/a", "example.com"),
        ("https://a.b.c.example.org", "example.org"),
        ("https://example.com./", "example.com"),
        ("https://www.bbc.co.uk/news", "bbc.co.uk"),
        ("https://bbc.co.uk", "bbc.co.uk"),
        ("https://shop.example.com.au", "example.com.au"),
        ("https://foo.github.io/project", "foo.github.io"),
        ("https://deep.foo.github.io", "foo.github.io"),
        ("https://app.vercel.app", "app.vercel.app"),
        ("https://github.io", "github.io"),
        ("https://co.uk", "co.uk"),
        ("https://localhost:3000/", "localhost"),
        ("http://192.168.1.10/admin", "192.168.1.10"),
        ("http://[::1]:8080/", "::1"),
    ] as [(String, String)])
    func findsTheSite(address: String, expected: String) {
        #expect(site(address) == expected)
    }

    @Test func subdomainsOfOneSiteAreTheSameSite() {
        #expect(site("https://mail.google.com") == site("https://google.com"))
        #expect(site("https://docs.example.com") == site("http://www.example.com"))
    }

    @Test func sitesOfOneHostingServiceOrCountryCodeAreDifferentSites() {
        #expect(site("https://foo.github.io") != site("https://bar.github.io"))
        #expect(site("https://a.co.uk") != site("https://b.co.uk"))
    }

    @Test func anIPAddressMatchesOnlyItself() {
        #expect(site("http://10.0.0.1") != site("http://10.0.0.2"))
        #expect(site("http://10.0.0.1:80/a") == site("https://10.0.0.1/b"))
    }

    @Test(arguments: ["about:blank", "file:///tmp/page.html", "mailto:someone@example.com", "ftp://example.com/",
                      "https:///path"])
    func anAddressThatIsNotAWebAddressHasNoSite(address: String) {
        #expect(site(address) == nil)
    }

    @Test func noAddressHasNoSite() {
        #expect(RegistrableDomain(nil) == nil)
    }
}
