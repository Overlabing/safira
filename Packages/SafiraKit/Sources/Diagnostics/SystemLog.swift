// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import OSLog

/// Where `DiagnosticLogger` hands a line meant for the unified system log. A seam so a test can see exactly what is
/// forwarded, which the system log itself cannot show.
public protocol SystemLog: Sendable {
    /// - Parameter isPrivate: the line is written with private privacy, so macOS redacts it unless the reader is
    ///   entitled to see it.
    func write(_ message: String, level: OSLogType, isPrivate: Bool)
}

struct OSLogSystemLog: SystemLog {
    private let logger: Logger

    init(subsystem: String) {
        logger = Logger(subsystem: subsystem, category: "diagnostics")
    }

    func write(_ message: String, level: OSLogType, isPrivate: Bool) {
        if isPrivate {
            logger.log(level: level, "\(message, privacy: .private)")
        } else {
            logger.log(level: level, "\(message, privacy: .public)")
        }
    }
}
