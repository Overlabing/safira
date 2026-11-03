// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Foundation
import SafiraCore
import SafiraSession
@testable import SafiraWeb
import Testing
import WebKit

/// Spike S6, measured against local servers and real WebKit. For an address typed without a scheme, with
/// `preferredHTTPSNavigationPolicy = .userMediatedFallbackToHTTP`:
///
/// | Host (port of the typed address)       | NSURLError | What WebKit does                 | HTTP requests before consent |
/// |----------------------------------------|------------|----------------------------------|------------------------------|
/// | answers TLS, certificate trusted       | none       | loads over HTTPS                 | 0                            |
/// | speaks plain HTTP only (TLS fails)     | -1200      | its own "Connection Is Not Secure" | 0                          |
/// | nothing listening (connection refused) | -1004      | the same warning                 | 0                            |
/// | accepts and never answers (timeout)    | -1001      | the same warning, after 60 s     | 0                            |
/// | self-signed certificate                | -1202      | the same warning                 | 0                            |
///
/// In every warned row the navigation delegate gets no failure callback. With the preference ignored
/// (`.keepAsRequested`) it gets the failure and nothing is shown, which is when Safira's own page takes over.
/// An `http://` request with the preference loads a blank page on loopback, so Safira never asks WebKit to upgrade.
@MainActor
@Suite(.serialized) struct HTTPSFirstTests {
    private let profileID = ProfileID(rawValue: UUID())

    /// A session whose Tabs are real web views. `policy` is what Safira asks WebKit for; `trustingCertificates`
    /// makes the throwaway certificate of the TLS server valid.
    @MainActor
    private final class Harness {
        private final class Pages { var byTab: [TabID: WebKitPage] = [:] }
        @MainActor private final class WindowBox {
            var windows: [NSWindow] = []
            func show(_ view: WKWebView) {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled],
                                      backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = view
                window.orderFrontRegardless()
                windows.append(window)
            }
        }

        let session: ProfileSession
        private let pages = Pages()
        /// WebKit shows its warning only for a web view that is in a window.
        private let windowBox: WindowBox

        init(profileID: ProfileID, policy: WKWebpagePreferences.UpgradeToHTTPSPolicy, trustingCertificates: Bool) {
            let context = ProfileWebContext(profileID: profileID)
            let pages = pages
            let windows = WindowBox()
            self.windowBox = windows
            session = ProfileSession(profile: Profile(id: profileID, name: "Test")) { id in
                let page = context.makePage(for: id)
                windows.show(page.webView)
                page.navigationHandler.httpsFirstPolicy = policy
                if trustingCertificates { page.navigationHandler.trustsServer = { _ in true } }
                pages.byTab[id] = page
                return page
            }
        }

        var page: WebKitPage? { session.selectedTabID.flatMap { pages.byTab[$0] } }
        var tab: Tab? { session.selectedTab }

        func title() async -> String? {
            try? await page?.webView.evaluateJavaScript("document.title") as? String
        }

        func close() {
            session.tabs.forEach { session.close($0.id) }
            windowBox.windows.forEach { $0.close() }
        }
    }

    private func settle(_ seconds: Double = 2) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func until(timeout: Double = 10, _ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// WebKit's own warning is a native overlay inside the web view.
    private func showsWebKitWarning(_ webView: WKWebView) -> Bool {
        webView.subviews.contains { String(describing: type(of: $0)).contains("Warning") }
    }

    /// Runs `body` with a fresh harness, then closes it and removes its data store once WebKit lets go of it.
    /// `removesStore` is false where WebKit shows its own warning: it did not release the store within 30 seconds of
    /// the window closing, so the store stays on disk until the test host exits.
    private func withHarness(policy: WKWebpagePreferences.UpgradeToHTTPSPolicy, trustingCertificates: Bool = false,
                             removesStore: Bool = true, _ body: (Harness) async throws -> Void) async throws {
        do {
            let harness = Harness(profileID: profileID, policy: policy, trustingCertificates: trustingCertificates)
            defer { harness.close() }
            try await body(harness)
        }
        if removesStore { try await removeDataStoreWhenReleased(profileID) }
    }

    @Test func anAddressWithNoSchemeLoadsOverHTTPSWhenTheHostAnswersTLS() async throws {
        let server = try await LocalServer.start(.tls, title: "secure")
        defer { server.stop() }
        try await withHarness(policy: .userMediatedFallbackToHTTP, trustingCertificates: true) { harness in
            harness.session.submitCommandBar("127.0.0.1:\(server.port)")

            #expect(await until { await harness.title() == "secure" })
            #expect(harness.tab?.address?.absoluteString == "https://127.0.0.1:\(server.port)/")
            #expect(harness.tab?.insecureConnectionWarning == nil)
            #expect(server.requestCount == 1)
        }
    }

    @Test func aHostWithoutTLSShowsWebKitsWarningBeforeAnyHTTPLoad() async throws {
        let server = try await LocalServer.start(.http, title: "insecure")
        defer { server.stop() }
        try await withHarness(policy: .userMediatedFallbackToHTTP, removesStore: false) { harness in
            harness.session.submitCommandBar("127.0.0.1:\(server.port)")

            let webView = try #require(harness.page?.webView)
            #expect(await until { showsWebKitWarning(webView) })
            await settle()
            #expect(server.requestCount == 0, "\(server.requestLines)")
            #expect(server.clientHelloCount >= 1)
            #expect(harness.tab?.insecureConnectionWarning == nil)
        }
    }

    @Test(arguments: ["refused", "selfSigned"])
    func aRefusedConnectionAndASelfSignedCertificateShowWebKitsWarningToo(host: String) async throws {
        let server: LocalServer? = switch host {
        case "selfSigned": try await LocalServer.start(.tls)
        default: nil
        }
        defer { server?.stop() }
        let closedPort = server == nil ? try await LocalServer.closedPort() : 0
        let port = server?.port ?? closedPort
        try await withHarness(policy: .userMediatedFallbackToHTTP, removesStore: false) { harness in
            harness.session.submitCommandBar("127.0.0.1:\(port)")

            let webView = try #require(harness.page?.webView)
            #expect(await until { showsWebKitWarning(webView) })
            #expect(harness.tab?.insecureConnectionWarning == nil)
        }
    }

    @Test func whenWebKitIgnoresThePolicyAHostWithoutTLSShowsSafirasWarningThenLoadsHTTPOnContinue() async throws {
        let server = try await LocalServer.start(.http, title: "insecure")
        defer { server.stop() }
        try await withHarness(policy: .keepAsRequested) { harness in
            harness.session.submitCommandBar("127.0.0.1:\(server.port)")

            #expect(await until { harness.tab?.insecureConnectionWarning != nil })
            #expect(await until { await harness.title()?.hasPrefix("No secure connection") == true })
            #expect(harness.tab?.insecureConnectionWarning?.reason == .noSecureConnection)
            #expect(harness.tab?.address?.absoluteString == "https://127.0.0.1:\(server.port)/")
            await settle(1)
            #expect(server.requestCount == 0, "\(server.requestLines)")

            // The user presses the link on the page.
            _ = try await harness.page?.webView.evaluateJavaScript(
                "document.getElementById('continue-over-http').click()")

            #expect(await until { await harness.title() == "insecure" })
            #expect(server.requestCount == 1)
            #expect(harness.tab?.address?.absoluteString == "http://127.0.0.1:\(server.port)/")
            #expect(harness.tab?.insecureConnectionWarning == nil)
        }
    }

    @Test(arguments: [("refused", InsecureConnectionWarning.Reason.noSecureConnection),
                      ("selfSigned", .invalidCertificate)])
    func whenWebKitIgnoresThePolicyARefusedConnectionAndASelfSignedCertificateShowSafirasWarning(
        host: String, reason: InsecureConnectionWarning.Reason
    ) async throws {
        let server: LocalServer? = host == "selfSigned" ? try await LocalServer.start(.tls) : nil
        defer { server?.stop() }
        let closedPort = server == nil ? try await LocalServer.closedPort() : 0
        let port = server?.port ?? closedPort
        try await withHarness(policy: .keepAsRequested) { harness in
            harness.session.submitCommandBar("127.0.0.1:\(port)")

            #expect(await until { harness.tab?.insecureConnectionWarning != nil })
            #expect(harness.tab?.insecureConnectionWarning?.reason == reason)
        }
    }

    @Test func anAddressTypedWithHTTPLoadsOverHTTPWithoutAWarning() async throws {
        let server = try await LocalServer.start(.http, title: "insecure")
        defer { server.stop() }
        try await withHarness(policy: .userMediatedFallbackToHTTP) { harness in
            harness.session.submitCommandBar("http://127.0.0.1:\(server.port)")

            #expect(await until { await harness.title() == "insecure" })
            #expect(harness.tab?.insecureConnectionWarning == nil)
            #expect(server.requestCount == 1)
        }
    }
}

/// WebKit refuses to remove a data store while a released web view's process still holds it; that takes a moment.
@MainActor
private func removeDataStoreWhenReleased(_ profile: ProfileID) async throws {
    for _ in 1..<50 {
        do {
            return try await ProfileWebContext.removeDataStore(of: profile)
        } catch {
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    try await ProfileWebContext.removeDataStore(of: profile)
}
