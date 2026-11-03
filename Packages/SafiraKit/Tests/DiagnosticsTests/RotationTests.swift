// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation
import Synchronization
import Testing

@Suite struct RotationTests {
    private static let limits = LogLimits(maxFileBytes: 400, maxAge: .seconds(7 * 24 * 3600), maxTotalBytes: 1_200)
    private static let day: TimeInterval = 24 * 3600

    private func logger(in directory: URL, limits: LogLimits = Self.limits, now: @escaping @Sendable () -> Date)
        -> DiagnosticLogger {
        DiagnosticLogger(subsystem: "test", logsDirectory: directory, limits: limits, isEnabled: true, clock: now)
    }

    @Test func aFileNeverGrowsPastItsLimit() {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = logger(in: directory) { Date() }

        for number in 0..<40 {
            logger.record(.memory(footprintBytes: UInt64(number)))
        }
        logger.flush()

        let files = logContents(in: directory)
        #expect(files.count > 1)
        for (name, text) in files {
            #expect(text.utf8.count <= Self.limits.maxFileBytes, "\(name) is over the file limit")
        }
    }

    @Test func theFolderNeverHoldsMoreThanTheTotalLimit() {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let start = Date()
        let tick = Mutex(0)
        let logger = logger(in: directory) { start.addingTimeInterval(Double(tick.withLock { $0 += 1; return $0 })) }

        for number in 0..<400 {
            logger.record(.memory(footprintBytes: UInt64(number)))
        }
        logger.flush()

        let files = logContents(in: directory)
        #expect(files.values.reduce(0) { $0 + $1.utf8.count } <= Self.limits.maxTotalBytes)
        // The newest lines survive, the oldest go.
        #expect(allLines(in: directory).last?.hasSuffix("footprint-bytes=399") == true)
        #expect(!allLines(in: directory).contains { $0.hasSuffix("footprint-bytes=0") })
    }

    @Test func aFileOlderThanSevenDaysIsDeletedWhenTheNextLineIsWritten() throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let now = Date()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let old = directory.appending(path: "safira-old.log")
        let recent = directory.appending(path: "safira-recent.log")
        for (file, age) in [(old, 7.5 * Self.day), (recent, 6.5 * Self.day)] {
            try Data("x".utf8).write(to: file)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: file.path)
        }
        let logger = logger(in: directory) { now }

        logger.record(.memory(footprintBytes: 1))
        logger.flush()

        let names = Set(logContents(in: directory).keys)
        #expect(!names.contains("safira-old.log"))
        #expect(names.contains("safira-recent.log"))
    }

    @Test func aRelaunchKeepsWritingToTheNewestFileWhileItHasRoom() {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let first = logger(in: directory) { Date() }
        first.record(.memory(footprintBytes: 1))
        first.flush()

        let second = logger(in: directory) { Date() }
        second.record(.memory(footprintBytes: 2))
        second.flush()

        #expect(logContents(in: directory).count == 1)
        #expect(allLines(in: directory).count == 2)
    }

    @Test func theStandardLimitsAreFiveMegabytesSevenDaysAndTwentyFive() {
        #expect(LogLimits.standard == LogLimits(maxFileBytes: 5_000_000, maxAge: .seconds(604_800),
                                                maxTotalBytes: 25_000_000))
    }
}
