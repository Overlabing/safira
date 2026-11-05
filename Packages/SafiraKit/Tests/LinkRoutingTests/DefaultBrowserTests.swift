// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DefaultApps
import Foundation
import LinkRouting
import Testing
import UniformTypeIdentifiers

private struct Refused: Error {}

private let xhtml = UTType("public.xhtml")!

private let appURL = URL(filePath: "/Applications/Safira.app")
private let safira = InstalledApplication(url: appURL, bundleIdentifier: "com.overlabing.safira", name: "Safira")
private let other = InstalledApplication(url: URL(filePath: "/Applications/Other.app"), bundleIdentifier: "com.example.other",
                                         name: "Other")

private func browser(_ system: any DefaultApplicationClient) -> DefaultBrowser {
    DefaultBrowser(client: system, applicationURL: appURL, bundleIdentifier: "com.overlabing.safira")
}

/// The app that LaunchServices hands a scheme or content type to, by name.
private func defaults(_ system: SimulatedDefaultApplications) async -> [String?] {
    [await system.defaultApplication(forScheme: "http")?.name, await system.defaultApplication(forScheme: "https")?.name,
     await system.defaultApplication(forContentType: .html)?.name, await system.defaultApplication(forContentType: xhtml)?.name]
}

@Suite struct DefaultBrowserTests {
    @Test func makingSafiraTheDefaultAsksForHTTPHTTPSAndHTMLFiles() async throws {
        let system = SimulatedDefaultApplications(installed: ["com.overlabing.safira": appURL])

        try await browser(system).makeDefault()

        #expect(await defaults(system) == ["Safira", "Safira", "Safira", "Safira"])
        #expect(await system.defaultApplication(forContentType: .html)?.bundleIdentifier == "com.overlabing.safira")
    }

    @Test func htmlFilesOpenedByAnotherAppMoveToSafiraWithTheSchemes() async throws {
        let system = SimulatedDefaultApplications(
            defaults: ["http": other, "https": other], contentTypes: ["public.html": other, "public.xhtml": other],
            installed: ["com.overlabing.safira": appURL])

        try await browser(system).makeDefault()

        #expect(await defaults(system) == ["Safira", "Safira", "Safira", "Safira"])
    }

    @Test func whereTheHTMLDefaultCannotBeChangedTheSchemesStillAreAndTheFailureIsReported() async {
        let system = SchemesOnly(SimulatedDefaultApplications(defaults: ["http": other, "https": other]))

        await #expect(throws: DefaultApplicationError.contentTypesNotSupported) { try await browser(system).makeDefault() }

        #expect(await system.simulated.defaultApplication(forScheme: "http")?.url == appURL)
        #expect(await system.simulated.defaultApplication(forScheme: "https")?.url == appURL)
        #expect(await browser(system).isDefault() == true)
    }

    @Test func safiraIsTheDefaultBrowserOnlyWhenItOpensBothHTTPAndHTTPS() async throws {
        let system = SimulatedDefaultApplications(defaults: ["http": other, "https": other])
        let browser = browser(system)
        #expect(await browser.isDefault() == false)

        system.setDefault(safira, forScheme: "http")
        #expect(await browser.isDefault() == false)

        try await browser.makeDefault()
        #expect(await browser.isDefault() == true)
    }

    @Test func anotherCopyOfSafiraThatIsTheDefaultCountsAsSafira() async {
        let copy = InstalledApplication(url: URL(filePath: "/tmp/Build/Products/Debug/Safira.app"),
                                        bundleIdentifier: "com.overlabing.safira", name: "Safira")
        let system = SimulatedDefaultApplications(defaults: ["http": copy, "https": copy])

        #expect(await browser(system).isDefault() == true)
    }

    @Test func aRefusedSchemeDoesNotStopTheOthersAndTheFailureIsReported() async {
        let system = SimulatedDefaultApplications(defaults: ["http": other, "https": other])
        let browser = browser(system)
        system.failNext(with: Refused())

        await #expect(throws: Refused.self) { try await browser.makeDefault() }

        #expect(await defaults(system) == ["Other", "Safira", "Safira", "Safira"])
        #expect(await browser.isDefault() == false)
    }
}

/// A client written before content types could be changed: it keeps the kit's default, which refuses them.
private struct SchemesOnly: DefaultApplicationClient {
    let simulated: SimulatedDefaultApplications
    init(_ simulated: SimulatedDefaultApplications) { self.simulated = simulated }

    func defaultApplication(forScheme scheme: String) async -> InstalledApplication? {
        await simulated.defaultApplication(forScheme: scheme)
    }
    func defaultApplication(forContentType type: UTType) async -> InstalledApplication? {
        await simulated.defaultApplication(forContentType: type)
    }
    func applicationURL(bundleIdentifier: String) async -> URL? { await simulated.applicationURL(bundleIdentifier: bundleIdentifier) }
    func openApplication(at url: URL) async throws { try await simulated.openApplication(at: url) }
    func makeDefault(_ url: URL, forScheme scheme: String) async throws { try await simulated.makeDefault(url, forScheme: scheme) }
}
