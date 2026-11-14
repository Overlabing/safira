// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

@Suite struct SafariUserAgentTests {
    @Test func theInstalledSafariVersionGivesSafarisOwnTokens() {
        #expect(SafariUserAgent.applicationName(safariVersion: "27.0.1", systemMajorVersion: 27)
            == "Version/27.0.1 Safari/605.1.15")
        #expect(SafariUserAgent.applicationName(safariVersion: "26.2", systemMajorVersion: 27)
            == "Version/26.2 Safari/605.1.15")
    }

    @Test func withoutAReadableSafariVersionTheSystemVersionStandsIn() {
        #expect(SafariUserAgent.applicationName(safariVersion: nil, systemMajorVersion: 27)
            == "Version/27.0 Safari/605.1.15")
        #expect(SafariUserAgent.applicationName(safariVersion: "", systemMajorVersion: 26)
            == "Version/26.0 Safari/605.1.15")
        #expect(SafariUserAgent.applicationName(safariVersion: "27.0 (beta)", systemMajorVersion: 27)
            == "Version/27.0 Safari/605.1.15")
        #expect(SafariUserAgent.applicationName(safariVersion: "27..1", systemMajorVersion: 27)
            == "Version/27.0 Safari/605.1.15")
    }

    @Test func aFolderWithoutABundleHasNoVersion() {
        #expect(SafariUserAgent.installedVersion(at: URL(filePath: "/nonexistent/Safari.app")) == nil)
    }

    @Test func theApplicationNameOfThisMacEndsWithSafarisToken() {
        #expect(SafariUserAgent.current.hasPrefix("Version/"))
        #expect(SafariUserAgent.current.hasSuffix(" Safari/605.1.15"))
    }
}
