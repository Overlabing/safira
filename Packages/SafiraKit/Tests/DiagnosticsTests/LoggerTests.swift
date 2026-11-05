// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import DiagnosticsKit
import Foundation
import Preferences
import SafiraCore
import Testing

@Suite struct LoggerTests {
    @Test func nothingIsCreatedWhileDebugModeIsOff() async throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = makeLogger(in: directory, isEnabled: false)
        let host = try #require(LoggedHost(url("https://example.com")))

        logger.record(.pageLoaded(host: host, milliseconds: 10))
        logger.record(.memory(footprintBytes: 1))
        await logger.sink.flush()

        #expect(logger.sink.isEnabled == false)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(try await logger.sink.hasLogs() == false)
    }

    @Test func theFirstLineMakesTheLogExportable() async throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = makeLogger(in: directory, isEnabled: false)
        #expect(try await logger.sink.hasLogs() == false)

        logger.setDebugMode(true)

        #expect(try await logger.sink.hasLogs())
    }

    @Test func turningDebugModeOffStopsLogging() async throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = makeLogger(in: directory, isEnabled: false)
        let host = try #require(LoggedHost(url("https://example.com")))

        logger.setDebugMode(true)
        logger.record(.pageLoaded(host: host, milliseconds: 10))
        logger.setDebugMode(false)
        logger.record(.pageLoaded(host: host, milliseconds: 20))
        logger.record(.memory(footprintBytes: 5))
        await logger.sink.flush()

        #expect(messages(in: directory) == [
            "notice [app] debug-mode on",
            "notice [navigation] page-loaded host=<private> ms=10",
            "notice [app] debug-mode off",
        ])
    }

    @Test func turningDebugModeOnTwiceWritesItsFirstLineOnce() async {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = makeLogger(in: directory, isEnabled: false)

        logger.setDebugMode(true)
        logger.setDebugMode(true)
        await logger.sink.flush()

        #expect(messages(in: directory) == ["notice [app] debug-mode on"])
    }

    @Test func aLineStartsWithAUTCTimestamp() async throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = makeLogger(in: directory, isEnabled: true)

        logger.record(.memory(footprintBytes: 7))
        await logger.sink.flush()

        let line = try #require(allLines(in: directory).first)
        #expect(line.wholeMatch(of: #/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z notice \[sample\] memory footprint-bytes=7/#)
            != nil)
    }

    @Test func theLoggerKeepsTheLinesOfEveryThreadInOrder() async throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let logger = makeLogger(in: directory, isEnabled: true)

        for number in 0..<200 {
            logger.record(.memory(footprintBytes: UInt64(number)))
        }
        await logger.sink.flush()

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
