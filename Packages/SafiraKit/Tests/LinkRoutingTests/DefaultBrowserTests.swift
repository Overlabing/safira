// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Testing

private struct Refused: Error {}

@MainActor
private final class RecordingRegistry: DefaultApplicationRegistry {
    var defaults: [String: URL] = [:]
    var refusedSchemes: Set<String> = []
    private(set) var schemeRequests: [String] = []
    private(set) var contentTypeRequests: [String] = []
    let appURL: URL

    init(appURL: URL) {
        self.appURL = appURL
    }

    func defaultApplication(forScheme scheme: String) -> URL? {
        defaults[scheme]
    }

    func setDefaultApplication(toOpenScheme scheme: String) async throws {
        schemeRequests.append(scheme)
        if refusedSchemes.contains(scheme) { throw Refused() }
        defaults[scheme] = appURL
    }

    func setDefaultApplication(toOpenContentType identifier: String) async throws {
        contentTypeRequests.append(identifier)
    }
}

private let appURL = URL(filePath: "/Applications/Safira.app")
private let otherBrowser = URL(filePath: "/Applications/Other.app")

@MainActor
@Suite struct DefaultBrowserTests {
    @Test func makingSafiraTheDefaultAsksForHTTPHTTPSAndHTMLFiles() async throws {
        let registry = RecordingRegistry(appURL: appURL)

        try await DefaultBrowser(registry: registry, appURL: appURL).makeDefault()

        #expect(registry.schemeRequests == ["http", "https"])
        #expect(registry.contentTypeRequests == ["public.html", "public.xhtml"])
    }

    @Test func safiraIsTheDefaultBrowserOnlyWhenItOpensBothHTTPAndHTTPS() async throws {
        let registry = RecordingRegistry(appURL: appURL)
        let browser = DefaultBrowser(registry: registry, appURL: appURL)
        registry.defaults = ["http": otherBrowser, "https": otherBrowser]
        #expect(browser.isDefault == false)

        registry.defaults = ["http": appURL, "https": otherBrowser]
        #expect(browser.isDefault == false)

        try await browser.makeDefault()
        #expect(browser.isDefault == true)
    }

    @Test func aRefusedSchemeDoesNotStopTheOthersAndTheFailureIsReported() async {
        let registry = RecordingRegistry(appURL: appURL)
        registry.refusedSchemes = ["http"]
        let browser = DefaultBrowser(registry: registry, appURL: appURL)

        await #expect(throws: Refused.self) { try await browser.makeDefault() }

        #expect(registry.schemeRequests == ["http", "https"])
        #expect(registry.contentTypeRequests == ["public.html", "public.xhtml"])
        #expect(browser.isDefault == false)
    }
}
