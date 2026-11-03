// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation
import Testing

@Suite struct MaskingTests {
    @Test func aFullAddressIsReducedToItsHost() {
        let address = url("https://user:hunter2@Mail.Example.com:8443/inbox/secret-thread?token=abc123#fragment")

        #expect(LoggedHost(address)?.name == "mail.example.com")
    }

    @Test func anAddressWithoutAHostHasNoLoggedHost() {
        #expect(LoggedHost(url("data:text/html,<title>Private</title>")) == nil)
        #expect(LoggedHost(url("file:///Users/someone/Documents/tax.pdf")) == nil)
    }

    @Test func aHostWithCharactersOutsideAHostNameIsRefused() {
        #expect(LoggedHost(url("https://exa%20mple.com/")) == nil)
        #expect(LoggedHost(url("https://%0Aforged.example/")) == nil)
    }

    @Test func aLoggedLineNamesTheHostAndNothingElseOfTheAddress() throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory, isEnabled: true)
        let address = url("https://user:hunter2@Mail.Example.com:8443/inbox/secret-thread?token=abc123#fragment")

        var tracker = PageLoadTracker()
        tracker.didCommit(url: address, at: .now)
        let finished = tracker.didFinish(at: .now)
        try logger.record(#require(finished))
        let failed = tracker.didFail(url: address, error: URLError(.cannotFindHost, userInfo: [
            NSLocalizedDescriptionKey: "Could not find https://mail.example.com/inbox/secret-thread?token=abc123",
            NSURLErrorFailingURLErrorKey: address,
        ]))
        logger.record(failed)
        logger.flush()

        let lines = allLines(in: directory)
        #expect(lines.count == 2)
        #expect(lines[0].contains(" notice page-loaded host=mail.example.com ms="))
        #expect(lines[1].hasSuffix(" error load-failed host=mail.example.com domain=NSURLErrorDomain code=-1003"))
        let text = lines.joined(separator: "\n")
        for forbidden in ["hunter2", "8443", "inbox", "secret-thread", "token", "abc123", "fragment", "https", "user"] {
            #expect(!text.contains(forbidden), "the log leaks \(forbidden)")
        }
    }

    @Test func everyEventCarriesTypedFieldsOnly() throws {
        // Every event carries typed fields; this is the whole set, and none holds free text from a page.
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory, isEnabled: true)
        let host = try #require(LoggedHost(url("https://example.com/Quarterly%20Report")))

        logger.record(.pageLoaded(host: host, milliseconds: 420))
        logger.record(.loadFailed(host: host, error: ErrorSummary(domain: "WKErrorDomain", code: 7)))
        logger.record(.tabCounts(TabCounts(blank: 1, loading: 2, loaded: 3)))
        logger.record(.memory(footprintBytes: 123_456_789))
        logger.flush()

        let text = allLines(in: directory).joined(separator: "\n")
        #expect(!text.contains("Quarterly"))
        #expect(!text.contains("Report"))
        #expect(text.contains("domain=WKErrorDomain code=7"))
        #expect(text.contains("tabs blank=1 loading=2 loaded=3"))
        #expect(text.contains("memory footprint-bytes=123456789"))
    }

    @Test func anErrorIsWrittenAsItsDomainAndCodeOnly() {
        let error = NSError(domain: "NSURLErrorDomain", code: -1200, userInfo: [
            NSLocalizedDescriptionKey: "An SSL error occurred connecting to https://bank.example/account?id=42",
        ])

        let summary = ErrorSummary(error)

        #expect(summary == ErrorSummary(domain: "NSURLErrorDomain", code: -1200))
        #expect(DiagnosticEvent.loadFailed(host: nil, error: summary).message
            == "load-failed host=- domain=NSURLErrorDomain code=-1200")
    }

    @Test func aNavigationTheUserReplacedIsNotAnError() {
        let cancelled = ErrorSummary(domain: NSURLErrorDomain, code: NSURLErrorCancelled)

        #expect(DiagnosticEvent.loadFailed(host: nil, error: cancelled).level == .notice)
        #expect(DiagnosticEvent.loadFailed(host: nil, error: ErrorSummary(domain: NSURLErrorDomain, code: -1003)).level == .error)
    }
}

@Test func anErrorDomainCannotForgeAnotherLogLine() {
    let summary = ErrorSummary(domain: "Evil\n2026-11-04T00:00:00Z error forged host=bank.example", code: 1)

    #expect(summary.domain == "Evil2026-11-04T000000Zerrorforgedhostbank.example")
    #expect(!DiagnosticEvent.loadFailed(host: nil, error: summary).message.contains("\n"))
    #expect(!DiagnosticEvent.loadFailed(host: nil, error: summary).message.contains(" forged"))
}
