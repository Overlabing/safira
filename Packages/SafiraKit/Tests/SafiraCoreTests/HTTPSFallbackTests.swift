// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

private func warning(_ address: String, code: URLError.Code, domain: String = NSURLErrorDomain)
    -> InsecureConnectionWarning? {
    HTTPSFallback.warning(after: LoadFailure(url: URL(string: address)!, domain: domain, code: code.rawValue))
}

@Test(arguments: [
    (URLError.Code.cannotConnectToHost, InsecureConnectionWarning.Reason.noSecureConnection),
    (.secureConnectionFailed, .noSecureConnection),
    (.timedOut, .noSecureConnection),
    (.networkConnectionLost, .noSecureConnection),
    (.serverCertificateUntrusted, .invalidCertificate),
    (.serverCertificateHasUnknownRoot, .invalidCertificate),
    (.serverCertificateHasBadDate, .invalidCertificate),
    (.serverCertificateNotYetValid, .invalidCertificate),
])
func aFailureOfTheSecureConnectionOffersHTTP(code: URLError.Code, reason: InsecureConnectionWarning.Reason) {
    let result = warning("https://example.com/page?q=1", code: code)

    #expect(result?.reason == reason)
    #expect(result?.httpURL.absoluteString == "http://example.com/page?q=1")
    #expect(result?.failedURL.absoluteString == "https://example.com/page?q=1")
    #expect(result?.host == "example.com")
}

@Test(arguments: [URLError.Code.cannotFindHost, .dnsLookupFailed, .notConnectedToInternet, .cancelled, .badURL,
                  .cannotParseResponse])
func aFailureHTTPWouldNotCureOffersNothing(code: URLError.Code) {
    #expect(warning("https://example.com", code: code) == nil)
}

@Test func theDefaultHTTPSPortIsDroppedAndAnyOtherPortKept() {
    #expect(warning("https://example.com:443/a", code: .cannotConnectToHost)?.httpURL.absoluteString == "http://example.com/a")
    #expect(warning("https://example.com:8443/a", code: .cannotConnectToHost)?.httpURL.absoluteString == "http://example.com:8443/a")
}

@Test func onlyAFailedHTTPSNavigationOffersHTTP() {
    #expect(warning("http://example.com", code: .cannotConnectToHost) == nil)
    #expect(warning("https://example.com", code: .cannotConnectToHost, domain: NSPOSIXErrorDomain) == nil)
}

@Test func anEmptyPathAndASlashAreTheSameAddress() {
    #expect(HTTPSFallback.isSameAddress(URL(string: "https://example.com")!, URL(string: "https://example.com/")!))
    #expect(HTTPSFallback.isSameAddress(URL(string: "https://example.com/a#x")!, URL(string: "https://example.com/a")!))
    #expect(!HTTPSFallback.isSameAddress(URL(string: "https://example.com/a")!, URL(string: "https://example.com/b")!))
    #expect(!HTTPSFallback.isSameAddress(URL(string: "https://example.com")!, URL(string: "http://example.com")!))
}
