// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import Testing

@Test func theEnginesAreOfferedInThisOrder() {
    #expect(SearchEngine.allCases.map(\.name) == ["DuckDuckGo", "Kagi", "Brave Search", "Google", "Ecosia"])
}

@Test(arguments: [
    (SearchEngine.duckDuckGo, "https://duckduckgo.com/?q=c%2B%2B%20%26%20rust%3D%3F"),
    (.kagi, "https://kagi.com/search?q=c%2B%2B%20%26%20rust%3D%3F"),
    (.braveSearch, "https://search.brave.com/search?q=c%2B%2B%20%26%20rust%3D%3F"),
    (.google, "https://www.google.com/search?q=c%2B%2B%20%26%20rust%3D%3F"),
    (.ecosia, "https://www.ecosia.org/search?q=c%2B%2B%20%26%20rust%3D%3F"),
])
func eachEngineGetsTheWholeQueryEncoded(engine: SearchEngine, expected: String) {
    #expect(engine.searchURL(for: "c++ & rust=?").absoluteString == expected)
}

@Test func aNewProfileHasNoSearchEngine() throws {
    let id = try #require(ProfileID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
    #expect(Profile(id: id, name: "Personal").searchEngine == nil)
}
