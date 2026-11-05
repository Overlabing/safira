// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import DiagnosticsKit
import Foundation
import Testing

@Suite struct LegacyLogFilesTests {
    private func write(_ names: [String], in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in names {
            try Data("2026-11-03T10:00:00.250Z notice page-loaded host=bank.example ms=1\n".utf8)
                .write(to: directory.appending(path: name))
        }
    }

    private func names(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    @Test func theOldFormatFilesAreDeletedAndEverythingElseStays() throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        try write([
            "safira-20261103T100000.250Z.log",
            "safira-20261103T100000.250Z-1.log",
            "safira-20261104T235959.999Z-12.log",
            "safira-2026-11-05.log",
            "safira-2026-11-05.1.log",
            "safira-20261103T100000.250Z.log.bak",
            "other-20261103T100000.250Z.log",
            "safira-20261103T100000Z.log",
            "notes.txt",
        ], in: directory)
        try FileManager.default.createDirectory(at: directory.appending(path: "safira-20261103T100000.250Z-2.log"),
                                                withIntermediateDirectories: false)

        LegacyLogFiles.remove(in: directory)

        #expect(names(in: directory) == [
            "notes.txt",
            "other-20261103T100000.250Z.log",
            "safira-2026-11-05.1.log",
            "safira-2026-11-05.log",
            "safira-20261103T100000.250Z-2.log",
            "safira-20261103T100000.250Z.log.bak",
            "safira-20261103T100000Z.log",
        ])
    }

    @Test func aMissingLogsFolderIsNotCreated() {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }

        LegacyLogFiles.remove(in: directory)

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func theKitStillWritesAndExportsItsOwnFilesAfterTheCleanup() async throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        try write(["safira-20261103T100000.250Z.log"], in: directory)
        let log = makeLog(in: directory, isEnabled: true)
        LegacyLogFiles.remove(in: directory)
        let logger = DiagnosticLogger(category: "navigation", sink: log)

        logger.record(.memory(footprintBytes: 1))
        await log.flush()

        #expect(try await log.logFiles().map(\.lastPathComponent) == [
            DiagnosticLogFiles.fileName(for: Date(), namePrefix: "safira"),
        ])
        #expect(!allLines(in: directory).joined().contains("bank.example"))
    }
}
