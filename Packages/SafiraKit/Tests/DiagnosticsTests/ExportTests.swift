// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation
import Testing

@Suite struct ExportTests {
    @Test func theExportIsAZipOfTheLogFiles() async throws {
        let directory = makeLogsDirectory()
        let workspace = FileManager.default.temporaryDirectory.appending(path: "safira-export-\(UUID().uuidString)")
        defer { removeParent(of: directory); try? FileManager.default.removeItem(at: workspace) }
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory, isEnabled: true)
        logger.record(.pageLoaded(host: LoggedHost(url("https://example.com/private?q=1")), milliseconds: 99))
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let archive = workspace.appending(path: "diagnostics.zip")

        try await logger.exportArchive(to: archive)

        let listing = try run("/usr/bin/unzip", ["-Z1", archive.path])
        #expect(listing.split(separator: "\n").count == 1)
        #expect(listing.contains(".log"))
        let extracted = workspace.appending(path: "out")
        _ = try run("/usr/bin/unzip", ["-q", archive.path, "-d", extracted.path])
        let text = allExtractedText(in: extracted)
        #expect(text.contains("page-loaded host=example.com ms=99"))
        #expect(!text.contains("private"))
    }

    @Test func exportingReplacesAnEarlierArchive() async throws {
        let directory = makeLogsDirectory()
        let workspace = FileManager.default.temporaryDirectory.appending(path: "safira-export-\(UUID().uuidString)")
        defer { removeParent(of: directory); try? FileManager.default.removeItem(at: workspace) }
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory, isEnabled: true)
        logger.record(.memory(footprintBytes: 1))
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let archive = workspace.appending(path: "diagnostics.zip")
        try Data("old".utf8).write(to: archive)

        try await logger.exportArchive(to: archive)

        #expect(try run("/usr/bin/unzip", ["-tq", archive.path]).contains("No errors"))
    }

    @Test func exportingWithoutLogsFailsInsteadOfWritingAnEmptyArchive() async throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let destination = FileManager.default.temporaryDirectory.appending(path: "never-\(UUID().uuidString).zip")
        let logger = DiagnosticLogger(subsystem: "test", logsDirectory: directory)

        await #expect(throws: DiagnosticsExportError.noLogs) {
            try await logger.exportArchive(to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    private func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func allExtractedText(in directory: URL) -> String {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        return (enumerator?.compactMap { $0 as? URL }.compactMap { try? String(contentsOf: $0, encoding: .utf8) } ?? [])
            .joined()
    }
}
