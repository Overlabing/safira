// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation
import OSLog
import Synchronization
import Testing

private final class RecordingSystemLog: SystemLog {
    struct Line: Equatable {
        let message: String
        let isPrivate: Bool
    }

    private let recorded = Mutex<[Line]>([])

    var lines: [Line] { recorded.withLock { $0 } }

    func write(_ message: String, level: OSLogType, isPrivate: Bool) {
        recorded.withLock { $0.append(Line(message: message, isPrivate: isPrivate)) }
    }
}

@Suite struct SystemLogTests {
    private let host = LoggedHost(url("https://alias.test/path"))
    private let failure = ErrorSummary(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)

    private func makeLogger(isEnabled: Bool, in directory: URL) -> (DiagnosticLogger, RecordingSystemLog) {
        let systemLog = RecordingSystemLog()
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory, isEnabled: isEnabled, systemLog: systemLog)
        return (logger, systemLog)
    }

    @Test func withDebugModeOffNoHostAndNoPageTimingReachesTheSystemLog() {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let (logger, systemLog) = makeLogger(isEnabled: false, in: directory)

        logger.record(.pageLoaded(host: host, milliseconds: 842))
        logger.record(.pageLoaded(host: nil, milliseconds: 17))
        logger.record(.loadFailed(host: host, error: failure))
        logger.flush()

        #expect(systemLog.lines == [])
    }

    @Test func withDebugModeOnSiteEventsReachTheSystemLogPrivateAndTheFile() {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let (logger, systemLog) = makeLogger(isEnabled: true, in: directory)

        logger.record(.pageLoaded(host: host, milliseconds: 842))
        logger.record(.loadFailed(host: host, error: failure))
        logger.flush()

        #expect(systemLog.lines == [
            .init(message: "page-loaded host=alias.test ms=842", isPrivate: true),
            .init(message: "load-failed host=alias.test domain=NSURLErrorDomain code=-1001", isPrivate: true),
        ])
        let lines = allLines(in: directory)
        #expect(lines.count == 2)
        #expect(lines[0].hasSuffix(" notice page-loaded host=alias.test ms=842"))
    }

    @Test func eventsWithoutSiteInformationReachTheSystemLogPublicWhateverTheMode() {
        for isEnabled in [false, true] {
            let directory = makeLogsDirectory()
            defer { removeParent(of: directory) }
            let (logger, systemLog) = makeLogger(isEnabled: isEnabled, in: directory)

            logger.record(.loadFailed(host: nil, error: failure))
            logger.record(.tabCounts(TabCounts(blank: 1, loading: 2, loaded: 3)))
            logger.record(.memory(footprintBytes: 9))
            logger.flush()

            #expect(systemLog.lines == [
                .init(message: "load-failed host=- domain=NSURLErrorDomain code=-1001", isPrivate: false),
                .init(message: "tabs blank=1 loading=2 loaded=3", isPrivate: false),
                .init(message: "memory footprint-bytes=9", isPrivate: false),
            ])
        }
    }

    @Test func switchingDebugModeOffStopsTheSiteEventsAndKeepsTheModeLines() {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let (logger, systemLog) = makeLogger(isEnabled: false, in: directory)

        logger.setEnabled(true)
        logger.record(.pageLoaded(host: host, milliseconds: 1))
        logger.setEnabled(false)
        logger.record(.pageLoaded(host: host, milliseconds: 2))
        logger.flush()

        #expect(systemLog.lines == [
            .init(message: "debug-mode on", isPrivate: false),
            .init(message: "page-loaded host=alias.test ms=1", isPrivate: true),
            .init(message: "debug-mode off", isPrivate: false),
        ])
    }

    @Test func theDefaultSystemLogNeverFailsTheLogger() {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory, isEnabled: true)

        logger.record(.pageLoaded(host: host, milliseconds: 3))
        logger.flush()

        #expect(allLines(in: directory).count == 1)
    }
}
