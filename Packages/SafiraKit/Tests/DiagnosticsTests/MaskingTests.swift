// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import DiagnosticsKit
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

    @Test func aLoggedLineKeepsTheHostOutOfTheFileAndTheRestOfTheAddressOutOfTheSystemLog() async throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let systemLog = RecordingSystemLog()
        let logger = makeLogger(in: directory, isEnabled: true, systemLog: systemLog)
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
        await logger.sink.flush()

        let lines = messages(in: directory)
        #expect(lines.count == 2)
        #expect(lines[0].hasPrefix("notice [navigation] page-loaded host=<private> ms="))
        #expect(lines[1] == "error [navigation] load-failed host=<private> domain=NSURLErrorDomain code=-1003")
        let full = systemLog.lines.compactMap(\.full)
        #expect(full.count == 2)
        #expect(full.first?.hasPrefix("page-loaded host=mail.example.com ms=") == true)
        #expect(full.last == "load-failed host=mail.example.com domain=NSURLErrorDomain code=-1003")
        let text = (lines + full).joined(separator: "\n")
        for forbidden in ["hunter2", "8443", "inbox", "secret-thread", "token", "abc123", "fragment", "https", "user"] {
            #expect(!text.contains(forbidden), "the log leaks \(forbidden)")
        }
        #expect(!lines.joined().contains("mail"))
    }

    @Test func everyEventCarriesTypedFieldsOnly() async throws {
        // Every event carries typed fields; this is the whole set, and none holds free text from a page.
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = makeLogger(in: directory, isEnabled: true)
        let host = try #require(LoggedHost(url("https://example.com/Quarterly%20Report")))

        logger.record(.pageLoaded(host: host, milliseconds: 420))
        logger.record(.loadFailed(host: host, error: ErrorSummary(domain: "WKErrorDomain", code: 7)))
        logger.record(.tabCounts(TabCounts(blank: 1, loading: 2, loaded: 3)))
        logger.record(.memory(footprintBytes: 123_456_789))
        await logger.sink.flush()

        let text = allLines(in: directory).joined(separator: "\n")
        #expect(!text.contains("Quarterly"))
        #expect(!text.contains("Report"))
        #expect(text.contains("domain=WKErrorDomain code=7"))
        #expect(text.contains("tabs blank=1 loading=2 loaded=3"))
        #expect(text.contains("memory footprint-bytes=123456789"))
    }

    @Test func everyHostAndPageTimingIsPrivateAndEveryOtherValuePublic() throws {
        let host = try #require(LoggedHost(url("https://example.com")))
        let failure = ErrorSummary(domain: "WKErrorDomain", code: 7)
        let events: [(DiagnosticEvent, isPrivate: Bool)] = [
            (.pageLoaded(host: host, milliseconds: 1), true),
            (.pageLoaded(host: nil, milliseconds: 1), true),
            (.loadFailed(host: host, error: failure), true),
            (.loadFailed(host: nil, error: failure), false),
            (.tabCounts(TabCounts()), false),
            (.memory(footprintBytes: 1), false),
            (.debugMode(isOn: true), false),
            (.linkRuleSkipped(index: 0, reason: .unknownProfile), false),
            (.linkRulesInvalid(.notJSON), false),
        ]

        for (event, isPrivate) in events {
            #expect(event.message.hasPrivate == isPrivate, "\(event)")
        }
        #expect(DiagnosticEvent.pageLoaded(host: nil, milliseconds: 1).message.redacted == "page-loaded host=<private> ms=1")
    }

    @Test func anErrorIsWrittenAsItsDomainAndCodeOnly() {
        let error = NSError(domain: "NSURLErrorDomain", code: -1200, userInfo: [
            NSLocalizedDescriptionKey: "An SSL error occurred connecting to https://bank.example/account?id=42",
        ])

        let summary = ErrorSummary(error)

        #expect(summary == ErrorSummary(domain: "NSURLErrorDomain", code: -1200))
        #expect(DiagnosticEvent.loadFailed(host: nil, error: summary).message.full
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
    #expect(!DiagnosticEvent.loadFailed(host: nil, error: summary).message.full.contains("\n"))
    #expect(!DiagnosticEvent.loadFailed(host: nil, error: summary).message.full.contains(" forged"))
}
