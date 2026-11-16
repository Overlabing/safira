// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Appearance
import Foundation
import Testing

/// Copy Link, on a pasteboard of the test's own: never the user's.
@MainActor
@Suite struct AddressPasteboardTests {
    private static func written(_ address: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("safira.test.\(UUID().uuidString)"))
        AddressPasteboard.write(URL(string: address)!, to: pasteboard)
        return pasteboard
    }

    @Test func aWebAddressIsTextAndAURL() {
        let pasteboard = Self.written("https://example.com/a?b=1")
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.string(forType: .string) == "https://example.com/a?b=1")
        #expect(pasteboard.string(forType: .URL) == "https://example.com/a?b=1")
        #expect(pasteboard.types?.contains(.fileURL) == false)
    }

    @Test func aFileAddressIsTextOnlyNeverAFile() {
        let pasteboard = Self.written("file:///tmp/page.html")
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.string(forType: .string) == "file:///tmp/page.html")
        // AppKit adds its legacy plain-text alias beside `.string`: what matters is that no URL type is there.
        #expect(pasteboard.types?.contains(.URL) == false)
        #expect(pasteboard.types?.contains(.fileURL) == false)
    }
}
