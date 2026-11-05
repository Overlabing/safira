// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DefaultApps
import Foundation
import LinkRouting
import Synchronization
import Testing
import UniformTypeIdentifiers

private struct Refused: Error {}

/// The HTML files Safira asked to open, in order.
private final class RecordingDocuments: DefaultDocumentApplications {
    private let requests = Mutex<[String]>([])
    var contentTypes: [String] { requests.withLock { $0 } }

    func makeDefault(_ application: URL, forContentType type: UTType) async throws {
        requests.withLock { $0.append(type.identifier) }
    }
}

private let appURL = URL(filePath: "/Applications/Safira.app")
private let safira = InstalledApplication(url: appURL, bundleIdentifier: "com.overlabing.safira", name: "Safira")
private let other = InstalledApplication(url: URL(filePath: "/Applications/Other.app"), bundleIdentifier: "com.example.other",
                                         name: "Other")

private func browser(_ system: SimulatedDefaultApplications, _ documents: RecordingDocuments = RecordingDocuments())
    -> DefaultBrowser {
    DefaultBrowser(client: system, documents: documents, applicationURL: appURL, bundleIdentifier: "com.overlabing.safira")
}

@Suite struct DefaultBrowserTests {
    @Test func makingSafiraTheDefaultAsksForHTTPHTTPSAndHTMLFiles() async throws {
        let system = SimulatedDefaultApplications(installed: ["com.overlabing.safira": appURL])
        let documents = RecordingDocuments()

        try await browser(system, documents).makeDefault()

        #expect(await system.defaultApplication(forScheme: "http")?.url == appURL)
        #expect(await system.defaultApplication(forScheme: "https")?.url == appURL)
        #expect(documents.contentTypes == ["public.html", "public.xhtml"])
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
        let documents = RecordingDocuments()
        let browser = browser(system, documents)
        system.failNext(with: Refused())

        await #expect(throws: Refused.self) { try await browser.makeDefault() }

        #expect(await system.defaultApplication(forScheme: "http")?.name == "Other")
        #expect(await system.defaultApplication(forScheme: "https")?.url == appURL)
        #expect(documents.contentTypes == ["public.html", "public.xhtml"])
        #expect(await browser.isDefault() == false)
    }
}
