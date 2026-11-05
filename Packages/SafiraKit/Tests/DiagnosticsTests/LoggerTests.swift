// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation
import Preferences
import SafiraCore
import Testing

@Suite struct LoggerTests {
    @Test func nothingIsCreatedWhileDebugModeIsOff() throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory)
        let host = try #require(LoggedHost(url("https://example.com")))

        logger.record(.pageLoaded(host: host, milliseconds: 10))
        logger.record(.memory(footprintBytes: 1))
        logger.flush()

        #expect(logger.isEnabled == false)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(!logger.hasLogs)
    }

    @Test func turningDebugModeOffStopsLogging() throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory)
        let host = try #require(LoggedHost(url("https://example.com")))

        logger.setEnabled(true)
        logger.record(.pageLoaded(host: host, milliseconds: 10))
        logger.setEnabled(false)
        logger.record(.pageLoaded(host: host, milliseconds: 20))
        logger.record(.memory(footprintBytes: 5))
        logger.flush()

        let lines = allLines(in: directory)
        #expect(lines.count == 3)
        #expect(lines[0].hasSuffix(" notice debug-mode on"))
        #expect(lines[1].hasSuffix("page-loaded host=example.com ms=10"))
        #expect(lines[2].hasSuffix(" notice debug-mode off"))
    }

    @Test func aLineStartsWithAUTCTimestamp() throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let moment = Date(timeIntervalSince1970: 1_793_700_000.25)
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory, isEnabled: true, clock: { moment })

        logger.record(.memory(footprintBytes: 7))
        logger.flush()

        #expect(allLines(in: directory) == ["2026-11-03T10:00:00.250Z info memory footprint-bytes=7"])
    }

    @Test func theLoggerKeepsTheLinesOfEveryThreadInOrder() throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory, isEnabled: true)

        for number in 0..<200 {
            logger.record(.memory(footprintBytes: UInt64(number)))
        }
        logger.flush()

        let bytes = allLines(in: directory).compactMap { $0.split(separator: "=").last.flatMap { UInt64($0) } }
        #expect(bytes == (0..<200).map(UInt64.init))
    }

    @Test func theProcessFootprintIsReadable() throws {
        let bytes = try #require(ProcessFootprint.currentBytes())
        #expect(bytes > 1_000_000)
    }

    @Test func theLoadTimeRunsFromCommitToFinish() throws {
        var tracker = PageLoadTracker()
        let start = ContinuousClock.now

        tracker.didCommit(url: url("https://example.com/a?b=c"), at: start)
        let event = tracker.didFinish(at: start.advanced(by: .milliseconds(842)))

        #expect(event == .pageLoaded(host: LoggedHost(url("https://example.com")), milliseconds: 842))
        #expect(tracker.didFinish(at: start.advanced(by: .seconds(5))) == nil)
    }

    @Test func aFailureEndsTheTimedLoad() {
        var tracker = PageLoadTracker()
        let start = ContinuousClock.now

        tracker.didCommit(url: url("https://example.com"), at: start)
        _ = tracker.didFail(url: url("https://example.com"), error: URLError(.timedOut))

        #expect(tracker.didFinish(at: start.advanced(by: .seconds(1))) == nil)
    }

    @Test func debugModeIsKeptAcrossLaunchesAndOffByDefault() {
        let values = InMemoryKeyValueStore()
        let store = DiagnosticsSettingsStore(store: values)

        #expect(store.load(unreadable: { _ in }).isDebugModeEnabled == false)

        store.save(DiagnosticsSettings(isDebugModeEnabled: true))

        #expect(DiagnosticsSettingsStore(store: values).load(unreadable: { _ in }).isDebugModeEnabled)
        #expect(values.data(forKey: "diagnostics.debugMode") == Data(#"{"isDebugModeEnabled":true}"#.utf8))
    }

    @Test func debugModeTheOldStoreKeptIsReadAfterTheMigration() throws {
        let domain = "safira-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "diagnostics.debugMode")

        LegacyPreference.migrate([DiagnosticsSettingsStore.legacy], in: defaults, domain: domain)

        #expect(DiagnosticsSettingsStore(store: defaults).load(unreadable: { _ in }).isDebugModeEnabled)
    }
}
