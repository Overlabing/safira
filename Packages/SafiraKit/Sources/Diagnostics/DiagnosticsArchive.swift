// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

public enum DiagnosticsExportError: Error, Equatable {
    case noLogs
    case archiveFailed
}

extension DiagnosticLogger {
    /// Writes the log files as a zip at `destination`, replacing a file already there. The zip is built off the
    /// caller's actor, and nothing leaves the machine: the user chose `destination`.
    public func exportArchive(to destination: URL) async throws {
        try await Task.detached {
            guard self.hasLogs else { throw DiagnosticsExportError.noLogs }
            var coordinationError: NSError?
            var failure: (any Error)?
            NSFileCoordinator().coordinate(readingItemAt: self.logsDirectory, options: .forUploading,
                                           error: &coordinationError) { zipped in
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: zipped, to: destination)
                } catch {
                    failure = error
                }
            }
            if let failure { throw failure }
            if coordinationError != nil { throw DiagnosticsExportError.archiveFailed }
        }.value
    }
}
