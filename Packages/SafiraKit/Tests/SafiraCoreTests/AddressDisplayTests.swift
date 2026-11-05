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

    @Test func aPathKeepsItsDecodedCharacters() {
        #expect(AddressDisplay(URL(string: "https://appstoreconnect.apple.com/apps")!).hostAndPath
                == "appstoreconnect.apple.com/apps")
    }
}
