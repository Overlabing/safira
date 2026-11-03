// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Dispatch
import Foundation
import Synchronization

/// Writes typed diagnostic events to rotating files while Debug mode is on, and to os_log unless they carry site
/// information while Debug mode is off.
/// It takes events, never strings or URLs, so what it can write is fixed by `DiagnosticEvent`.
public final class DiagnosticLogger: Sendable {
    private let systemLog: any SystemLog
    private let isOn: Mutex<Bool>
    private let files: Mutex<LogFileStore>
    private let queue = DispatchQueue(label: "diagnostics.log-writer")
    private let clock: @Sendable () -> Date
    let logsDirectory: URL

    /// - Parameters:
    ///   - subsystem: the os_log subsystem, the bundle identifier.
    ///   - logsDirectory: not created until the first line is written.
    ///   - systemLog: where os_log lines go; the unified system log under `subsystem` when nil.
    public init(subsystem: String, logsDirectory: URL, limits: LogLimits = .standard, isEnabled: Bool = false,
                systemLog: (any SystemLog)? = nil, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.systemLog = systemLog ?? OSLogSystemLog(subsystem: subsystem)
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
        let enabled = isEnabled
        // macOS keeps notice-level lines on disk, so with Debug mode off a host or a page timing must not reach it at
        // all; with it on, they reach it private.
        if !event.carriesSiteInformation {
            systemLog.write(event.message, level: event.level.osLogType, isPrivate: false)
        } else if enabled {
            systemLog.write(event.message, level: event.level.osLogType, isPrivate: true)
        }
        guard enabled else { return }
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
