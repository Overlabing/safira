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

        #expect(try await browser(system).makeDefault() == .accepted)

        #expect(await defaults(system) == ["Safira", "Safira", "Safira", "Safira"])
        #expect(await system.defaultApplication(forContentType: .html)?.bundleIdentifier == "com.overlabing.safira")
    }

    @Test func htmlFilesOpenedByAnotherAppMoveToSafiraWithTheSchemes() async throws {
        let system = SimulatedDefaultApplications(
            defaults: ["http": other, "https": other], contentTypes: ["public.html": other, "public.xhtml": other],
            installed: ["com.overlabing.safira": appURL])

        #expect(try await browser(system).makeDefault() == .accepted)

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

        #expect(try await browser.makeDefault() == .accepted)
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

    /// Keep in the system's confirmation, as measured on an HTML request: Cocoa error 256 over `userCanceledErr`.
    @Test func keepingTheCurrentBrowserIsADeclineAndNothingMoreIsAsked() async throws {
        let system = SimulatedDefaultApplications(defaults: ["http": other, "https": other],
                                                  contentTypes: ["public.html": other, "public.xhtml": other])
        let cancelled = NSError(domain: NSOSStatusErrorDomain, code: -128)
        system.failNext(with: NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSUnderlyingErrorKey: cancelled]))

        #expect(try await browser(system).makeDefault() == .declined)

        #expect(await defaults(system) == ["Other", "Other", "Other", "Other"], "no request after the decline")
        #expect(await browser(system).isDefault() == false)
    }

    @Test func userCanceledErrOnItsOwnIsADeclineToo() async throws {
        let system = SimulatedDefaultApplications(defaults: ["http": other, "https": other])
        system.failNext(with: NSError(domain: NSOSStatusErrorDomain, code: -128))

        #expect(try await browser(system).makeDefault() == .declined)
        #expect(await defaults(system) == ["Other", "Other", nil, nil])
    }

    /// Only the cancellation is a decline: another error under the same Cocoa wrapper is still a failure.
    @Test func anotherWrappedErrorIsStillAFailure() async {
        let system = SimulatedDefaultApplications(defaults: ["http": other, "https": other])
        let denied = NSError(domain: NSOSStatusErrorDomain, code: -54)
        system.failNext(with: NSError(domain: NSCocoaErrorDomain, code: 256, userInfo: [NSUnderlyingErrorKey: denied]))

        await #expect(throws: NSError.self) { try await browser(system).makeDefault() }

        #expect(await defaults(system) == ["Other", "Safira", "Safira", "Safira"])
    }

    /// A second request after a decline asks again: Safira itself never repeats it, only the explicit button does.
    @Test func askingAgainAfterADeclineAsksTheSystemAgain() async throws {
        let system = SimulatedDefaultApplications(defaults: ["http": other, "https": other])
        let browser = browser(system)
        system.failNext(with: NSError(domain: NSOSStatusErrorDomain, code: -128))
        #expect(try await browser.makeDefault() == .declined)

        #expect(try await browser.makeDefault() == .accepted)
        #expect(await browser.isDefault() == true)
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
