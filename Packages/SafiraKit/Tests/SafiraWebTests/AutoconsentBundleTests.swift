// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraWeb
import Testing

@Suite struct AutoconsentBundleTests {
    @Test func theVendoredScriptCannotReachTheNetworkByItself() {
        let script = AutoconsentBundle.script
        for api in ["fetch(", "XMLHttpRequest", "sendBeacon", "WebSocket", "EventSource", "importScripts", "new Image"] {
            #expect(!script.contains(api), "the bundle uses \(api)")
        }
    }

    @Test func theVendoredScriptTalksThroughTheSenderSafiraProvides() {
        #expect(AutoconsentBundle.script.contains("window.autoconsentSendMessage"))
        #expect(AutoconsentBundle.script.contains("window.autoconsentReceiveMessage ="))
    }

    @Test func theCompactRulesAreTheWholePinnedList() throws {
        let rules = try #require(
            try JSONSerialization.jsonObject(with: Data(AutoconsentBundle.compactRules.utf8)) as? [String: Any])
        #expect(rules["v"] as? Int == 1)
        #expect((rules["r"] as? [Any])?.count == 1609)
        #expect(AutoconsentBundle.version == "18.5.0")
    }
}
