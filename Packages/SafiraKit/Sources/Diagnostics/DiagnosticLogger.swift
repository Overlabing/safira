// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Dispatch
import Foundation
import OSLog
import Synchronization

/// Writes typed diagnostic events to os_log and, only while Debug mode is on, to rotating files.
/// It takes events, never strings or URLs, so what it can write is fixed by `DiagnosticEvent`.
public final class DiagnosticLogger: Sendable {
    private let osLogger: Logger
    private let isOn: Mutex<Bool>
    private let files: Mutex<LogFileStore>
    private let queue = DispatchQueue(label: "diagnostics.log-writer")
    private let clock: @Sendable () -> Date
    let logsDirectory: URL

    /// - Parameters:
    ///   - subsystem: the os_log subsystem, the bundle identifier.
    ///   - logsDirectory: not created until the first line is written.
    public init(subsystem: String, logsDirectory: URL, limits: LogLimits = .standard, isEnabled: Bool = false,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        osLogger = Logger(subsystem: subsystem, category: "diagnostics")
        isOn = Mutex(isEnabled)
        files = Mutex(LogFileStore(directory: logsDirectory, limits: limits))
        self.logsDirectory = logsDirectory
        self.clock = clock
    }

    public var isEnabled: Bool {
        isOn.withLock { $0 }
    }

    /// Turning it on writes the first line; turning it off writes the last one. While off, nothing is written.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled {
            isOn.withLock { $0 = true }
            record(.debugMode(isOn: true))
        } else {
            record(.debugMode(isOn: false))
            isOn.withLock { $0 = false }
        }
    }

    public func record(_ event: DiagnosticEvent) {
        osLogger.log(level: event.level.osLogType, "\(event.message, privacy: .public)")
        guard isEnabled else { return }
        let now = clock()
        let line = "\(now.formatted(Self.timestampStyle)) \(event.level.rawValue) \(event.message)\n"
        queue.async {
            // A full disk or a removed folder must never take the browser down.
            try? self.files.withLock { try $0.append(line, at: now) }
        }
    }

    /// Returns once every line recorded so far is on disk.
    public func flush() {
        queue.sync {}
    }

    /// Whether any log file exists.
    public var hasLogs: Bool {
        flush()
        return !LogFileStore.logFiles(in: logsDirectory).isEmpty
    }

    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt)
}
