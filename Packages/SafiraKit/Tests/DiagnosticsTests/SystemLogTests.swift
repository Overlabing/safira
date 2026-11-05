// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import DiagnosticsKit
import Foundation
import OSLog
import Testing

@Suite struct SystemLogTests {
    private let host = LoggedHost(url("https://alias.test/path"))
    private let failure = ErrorSummary(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)

    @Test func safiraLetsAPublicLineAlwaysReachTheSystemLogAndAPrivateOneOnlyInDebugMode() {
        #expect(DiagnosticsConfiguration.safira(subsystem: "com.overlabing.safira") == DiagnosticsConfiguration(
            subsystem: "com.overlabing.safira", fileNamePrefix: "safira", archiveName: "Safira",
            limits: DiagnosticLogFiles.Limits(keepDays: 7, maxFileBytes: 5_000_000, maxTotalBytes: 25_000_000),
            osLog: .publicMessagesAlways))
    }

    @Test func withDebugModeOffAFailedLoadWithAHostNeverReachesTheSystemLog() async {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let systemLog = RecordingSystemLog()
        let logger = makeLogger(in: directory, isEnabled: false, systemLog: systemLog)

        logger.record(.loadFailed(host: LoggedHost(url("https://bank.example/account?id=42")), error: failure))
        await logger.sink.flush()

        #expect(systemLog.lines == [])
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func withDebugModeOffNoHostAndNoPageTimingReachesTheSystemLog() async {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let systemLog = RecordingSystemLog()
        let logger = makeLogger(in: directory, isEnabled: false, systemLog: systemLog)

        logger.record(.pageLoaded(host: host, milliseconds: 842))
        logger.record(.pageLoaded(host: nil, milliseconds: 17))
        logger.record(.loadFailed(host: host, error: failure))
        await logger.sink.flush()

        #expect(systemLog.lines == [])
    }

    @Test func withDebugModeOnSiteEventsReachTheSystemLogPrivateAndTheFileWithoutTheirHost() async {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let systemLog = RecordingSystemLog()
        let logger = makeLogger(in: directory, isEnabled: true, systemLog: systemLog)

        logger.record(.pageLoaded(host: host, milliseconds: 842))
        logger.record(.loadFailed(host: host, error: failure))
        await logger.sink.flush()

        #expect(systemLog.lines == [
            .init(category: "navigation", type: .default, redacted: "page-loaded host=<private> ms=842",
                  full: "page-loaded host=alias.test ms=842"),
            .init(category: "navigation", type: .error,
                  redacted: "load-failed host=<private> domain=NSURLErrorDomain code=-1001",
                  full: "load-failed host=alias.test domain=NSURLErrorDomain code=-1001"),
        ])
        #expect(messages(in: directory) == [
            "notice [navigation] page-loaded host=<private> ms=842",
            "error [navigation] load-failed host=<private> domain=NSURLErrorDomain code=-1001",
        ])
    }

    @Test(arguments: [false, true])
    func eventsWithoutSiteInformationReachTheSystemLogPublicWhateverTheMode(isEnabled: Bool) async {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let systemLog = RecordingSystemLog()
        let logger = makeLogger(in: directory, isEnabled: isEnabled, systemLog: systemLog)

        logger.record(.loadFailed(host: nil, error: failure))
        logger.record(.tabCounts(TabCounts(blank: 1, loading: 2, loaded: 3)))
        logger.record(.memory(footprintBytes: 9))
        await logger.sink.flush()

        #expect(systemLog.lines == [
            .init(category: "navigation", type: .error, redacted: "load-failed host=- domain=NSURLErrorDomain code=-1001",
                  full: nil),
            .init(category: "sample", type: .default, redacted: "tabs blank=1 loading=2 loaded=3", full: nil),
            .init(category: "sample", type: .default, redacted: "memory footprint-bytes=9", full: nil),
        ])
    }

    @Test func switchingDebugModeOffStopsTheSiteEventsAndKeepsTheModeLines() async {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let systemLog = RecordingSystemLog()
        let logger = makeLogger(in: directory, isEnabled: false, systemLog: systemLog)

        logger.setDebugMode(true)
        logger.record(.pageLoaded(host: host, milliseconds: 1))
        logger.setDebugMode(false)
        logger.record(.pageLoaded(host: host, milliseconds: 2))
        await logger.sink.flush()

        #expect(systemLog.lines == [
            .init(category: "app", type: .default, redacted: "debug-mode on", full: nil),
            .init(category: "navigation", type: .default, redacted: "page-loaded host=<private> ms=1",
                  full: "page-loaded host=alias.test ms=1"),
            .init(category: "app", type: .default, redacted: "debug-mode off", full: nil),
        ])
    }

    @Test func theDefaultSystemLogNeverFailsTheLog() async {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let log = DiagnosticLog(configuration: .safira(subsystem: "test"), isEnabled: true)
        log.start { directory }
        let logger = DiagnosticLogger(category: "navigation", sink: log)

        logger.record(.pageLoaded(host: host, milliseconds: 3))
        await log.flush()

        #expect(messages(in: directory) == ["notice [navigation] page-loaded host=<private> ms=3"])
    }
}
