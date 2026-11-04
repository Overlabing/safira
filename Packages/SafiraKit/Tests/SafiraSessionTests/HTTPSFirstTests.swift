// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import Testing

@MainActor
@Suite struct HTTPSFirstTests {
    @Test func anAddressTypedWithoutASchemeAsksThePageForHTTPSFirst() throws {
        let fixture = SessionFixture()

        fixture.session.submitCommandBar("example.com")

        let load = try #require(fixture.selectedPage?.loads.first)
        #expect(load.url.absoluteString == "https://example.com")
        #expect(load.httpsFirst)
    }

    @Test(arguments: ["https://example.com", "http://example.com"])
    func anAddressTypedWithASchemeLoadsAsTyped(text: String) throws {
        let fixture = SessionFixture()

        fixture.session.submitCommandBar(text)

        let load = try #require(fixture.selectedPage?.loads.first)
        #expect(load.url.absoluteString == text)
        #expect(!load.httpsFirst)
    }

    @Test func aSearchLoadsAsGiven() throws {
        let fixture = SessionFixture(searchEngine: .kagi)

        fixture.session.submitCommandBar("swift testing")

        #expect(fixture.selectedPage?.loads.first?.httpsFirst == false)
    }

    @Test func whenHTTPSFailsTheTabWarnsAndLoadsNothingOverHTTP() throws {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com/a")
        let page = try #require(fixture.selectedPage)

        page.failLoad(of: URL(string: "https://example.com/a")!, code: .cannotConnectToHost)

        let tab = try #require(fixture.session.selectedTab)
        #expect(tab.insecureConnectionWarning?.httpURL.absoluteString == "http://example.com/a")
        #expect(tab.insecureConnectionWarning?.reason == .noSecureConnection)
        #expect(page.shownWarnings == [try #require(tab.insecureConnectionWarning)])
        #expect(page.loads.map(\.url.absoluteString) == ["https://example.com/a"])
    }

    @Test func aCertificateFailureWarnsWithItsOwnReason() throws {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")

        fixture.selectedPage?.failLoad(of: URL(string: "https://example.com")!, code: .serverCertificateUntrusted)

        #expect(fixture.session.selectedTab?.insecureConnectionWarning?.reason == .invalidCertificate)
    }

    @Test func continuingLoadsTheHTTPAddressAndClearsTheWarning() throws {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com:8080/a")
        let page = try #require(fixture.selectedPage)
        page.failLoad(of: URL(string: "https://example.com:8080/a")!, code: .secureConnectionFailed)

        page.pressContinueOverHTTP()

        let load = try #require(page.loads.last)
        #expect(load.url.absoluteString == "http://example.com:8080/a")
        #expect(!load.httpsFirst)
        #expect(page.loads.count == 2)
        #expect(fixture.session.selectedTab?.insecureConnectionWarning == nil)
    }

    @Test func nothingLoadsOverHTTPWithoutTheUsersChoice() throws {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")
        let page = try #require(fixture.selectedPage)

        page.failLoad(of: URL(string: "https://example.com")!, code: .cannotConnectToHost)
        fixture.session.reload()

        #expect(page.loads.allSatisfy { $0.url.scheme == "https" })
        #expect(page.loadCount == 1)
    }

    @Test func continuingWithoutAWarningDoesNothing() throws {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")
        let page = try #require(fixture.selectedPage)

        page.pressContinueOverHTTP()

        #expect(page.loadCount == 1)
    }

    @Test func aFailureOfAnAddressTypedWithAnHTTPSSchemeOffersNothing() throws {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("https://example.com")

        fixture.selectedPage?.failLoad(of: URL(string: "https://example.com")!, code: .cannotConnectToHost)

        #expect(fixture.session.selectedTab?.insecureConnectionWarning == nil)
        #expect(fixture.selectedPage?.shownWarnings.isEmpty == true)
    }

    @Test func aFailureOfAnotherAddressOffersNothing() throws {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")

        fixture.selectedPage?.failLoad(of: URL(string: "https://other.example")!, code: .cannotConnectToHost)

        #expect(fixture.session.selectedTab?.insecureConnectionWarning == nil)
    }

    @Test func aFailureHTTPWouldNotCureOffersNothing() throws {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")

        fixture.selectedPage?.failLoad(of: URL(string: "https://example.com")!, code: .cannotFindHost)

        #expect(fixture.session.selectedTab?.insecureConnectionWarning == nil)
    }

    @Test func aNewAddressClearsTheWarning() throws {
        let fixture = SessionFixture()
        fixture.session.submitCommandBar("example.com")
        fixture.selectedPage?.failLoad(of: URL(string: "https://example.com")!, code: .cannotConnectToHost)

        fixture.session.submitCommandBar("swift.org")

        #expect(fixture.session.selectedTab?.insecureConnectionWarning == nil)
    }
}
