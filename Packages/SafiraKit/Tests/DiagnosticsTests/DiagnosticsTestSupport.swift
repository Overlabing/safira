// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import DiagnosticsKit
import Foundation
import OSLog
import Synchronization

/// What reached the system log, which the system log itself cannot show.
final class RecordingSystemLog: DiagnosticSystemLog {
    struct Line: Equatable {
        let category: String
        let type: OSLogType
        let redacted: String
        /// The form with private values, written private; nil when the line has none.
        let full: String?
    }

    private let recorded = Mutex<[Line]>([])

    var lines: [Line] { recorded.withLock { $0 } }

    func channel(category: String) -> any DiagnosticSystemLogChannel {
        Channel(category: category, log: self)
    }

    private struct Channel: DiagnosticSystemLogChannel {
        let category: String
        let log: RecordingSystemLog

        func isEnabled(_ type: OSLogType) -> Bool { true }

        func write(_ type: OSLogType, redacted: String, full: String?) {
            log.recorded.withLock { $0.append(Line(category: category, type: type, redacted: redacted, full: full)) }
        }
    }
}

/// Safira's log, started in `directory`, with the system log behind the recording seam.
func makeLog(in directory: URL, isEnabled: Bool, systemLog: RecordingSystemLog = RecordingSystemLog()) -> DiagnosticLog {
    let log = DiagnosticLog(configuration: .safira(subsystem: "test"), flushDelay: .milliseconds(10),
                            isEnabled: isEnabled, systemLog: systemLog)
    log.start { directory }
    return log
}

func makeLogger(in directory: URL, isEnabled: Bool, systemLog: RecordingSystemLog = RecordingSystemLog())
    -> DiagnosticLogger {
    DiagnosticLogger(category: "navigation", sink: makeLog(in: directory, isEnabled: isEnabled, systemLog: systemLog))
}

/// A throwaway folder that does not exist until a test or the log creates it.
func makeLogsDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "safira-diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: "Logs", directoryHint: .isDirectory)
}

func removeParent(of logs: URL) {
    try? FileManager.default.removeItem(at: logs.deletingLastPathComponent())
}

func logContents(in directory: URL) -> [String: String] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return Dictionary(uniqueKeysWithValues: names.map { name in
        (name, (try? String(contentsOf: directory.appending(path: name), encoding: .utf8)) ?? "")
    })
}

func allLines(in directory: URL) -> [String] {
    logContents(in: directory).sorted { $0.key < $1.key }.flatMap { $0.value.split(separator: "\n").map(String.init) }
}

/// The lines without their timestamp, which the kit takes from the clock: `notice [navigation] page-loaded …`.
func messages(in directory: URL) -> [String] {
    allLines(in: directory).map { String($0.split(separator: " ", maxSplits: 1).last ?? "") }
}

func url(_ string: String) -> URL {
    URL(string: string)!
}
