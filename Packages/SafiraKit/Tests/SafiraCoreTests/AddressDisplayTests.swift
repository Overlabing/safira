// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

@Suite struct AddressDisplayTests {
    @Test func thePillShowsTheHostOnly() {
        let display = AddressDisplay(URL(string: "https://www.google.com/search?client=firefox-b-d&q=zen+browser")!)

        #expect(display.host == "www.google.com")
    }

    @Test func anAddressWithoutAHostIsShownWhole() {
        #expect(AddressDisplay(URL(string: "about:blank")!).host == "about:blank")
        #expect(AddressDisplay(URL(string: "about:blank")!).hostAndPath == "about:blank")
    }

    @Test func aSuggestionRowShowsTheHostAndThePathWithoutQueryOrScheme() {
        let display = AddressDisplay(URL(string: "https://media.example.com/web/?x=1#/home")!)

        #expect(display.hostAndPath == "media.example.com/web/")
    }

    @Test func aLoneSlashIsDropped() {
        #expect(AddressDisplay(URL(string: "https://youtube.com/")!).hostAndPath == "youtube.com")
        #expect(AddressDisplay(URL(string: "https://youtube.com")!).hostAndPath == "youtube.com")
    }

    @Test func onlyAPlainHTTPPageIsMarkedNotSecure() {
        #expect(AddressDisplay(URL(string: "http://example.com/")!).isNotSecure)
        #expect(AddressDisplay(URL(string: "HTTP://example.com/")!).isNotSecure)
        #expect(!AddressDisplay(URL(string: "https://example.com/")!).isNotSecure)
        #expect(!AddressDisplay(URL(string: "about:blank")!).isNotSecure)
        #expect(!AddressDisplay(URL(string: "file:///tmp/page.html")!).isNotSecure)
    }

    @Test func aLoopbackHostIsASecureContextAndCarriesNoMark() {
        for address in ["http://localhost:8080/", "http://LOCALHOST/", "http://app.localhost/", "http://127.0.0.1/",
                        "http://127.1.2.3:3000/x", "http://[::1]:8080/"] {
            #expect(!AddressDisplay(URL(string: address)!).isNotSecure, "\(address)")
        }
        for address in ["http://localhost.example.com/", "http://128.0.0.1/", "http://127.0.0.1.example.com/",
                        "http://10.0.0.1/", "http://[::2]/"] {
            #expect(AddressDisplay(URL(string: address)!).isNotSecure, "\(address)")
        }
    }

    @Test func onlyAnHTTPOrHTTPSAddressIsAWebAddress() {
        #expect(AddressDisplay(URL(string: "https://example.com/")!).isWebAddress)
        #expect(AddressDisplay(URL(string: "http://example.com/")!).isWebAddress)
        #expect(!AddressDisplay(URL(string: "file:///tmp/page.html")!).isWebAddress)
        #expect(!AddressDisplay(URL(string: "about:blank")!).isWebAddress)
    }

    @Test func aPathKeepsItsDecodedCharacters() {
        #expect(AddressDisplay(URL(string: "https://appstoreconnect.apple.com/apps")!).hostAndPath
                == "appstoreconnect.apple.com/apps")
    }
}
