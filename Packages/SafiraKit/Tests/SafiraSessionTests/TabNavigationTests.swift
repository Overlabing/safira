// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraSession
import Testing

@MainActor
private final class SimulatedPage: WebPageHandle {
    private(set) var loadedURLs: [URL] = []

    func load(_ url: URL) {
        loadedURLs.append(url)
    }
}

@MainActor
@Test func openingAnAddressLoadsItInThePageAndRecordsIt() throws {
    let page = SimulatedPage()
    let tab = TabNavigation(page: page)
    let url = try #require(URL(string: "https://example.com/"))

    tab.open(url)

    #expect(page.loadedURLs.map(\.absoluteString) == ["https://example.com/"])
    #expect(tab.address?.absoluteString == "https://example.com/")
}
