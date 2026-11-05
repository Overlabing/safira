// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import DiagnosticsKit
import Foundation
import Testing

@Suite struct ExportTests {
    private static let moment = Date(timeIntervalSince1970: 1_793_700_000)
    private static let environment = DiagnosticEnvironment.text(
        appVersion: "0.1.0", build: "1", system: OperatingSystemVersion(majorVersion: 27, minorVersion: 1, patchVersion: 0))

    @Test func theExportIsTheKitsZipOfTheLogFilesTheEnvironmentAndTheSummary() async throws {
        let directory = makeLogsDirectory()
        let workspace = FileManager.default.temporaryDirectory.appending(path: "safira-export-\(UUID().uuidString)")
        defer { removeParent(of: directory); try? FileManager.default.removeItem(at: workspace) }
        let logger = makeLogger(in: directory, isEnabled: true)
        logger.record(.pageLoaded(host: LoggedHost(url("https://example.com/secret-path?q=1")), milliseconds: 99))
        logger.record(.loadFailed(host: nil, error: ErrorSummary(domain: "WKErrorDomain", code: 7)))
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let archive = workspace.appending(path: "diagnostics.zip")

        try await logger.sink.export(environment: Self.environment, requireLogs: true, to: archive, now: Self.moment)

        let logFile = DiagnosticLogFiles.fileName(for: Date(), namePrefix: "safira")
        let listing = try run("/usr/bin/zipinfo", ["-1", archive.path]).split(separator: "\n").map(String.init).sorted()
        #expect(listing == [
            "Safira-diagnostics-20261103-100000/environment.txt",
            "Safira-diagnostics-20261103-100000/\(logFile)",
            "Safira-diagnostics-20261103-100000/summary.txt",
        ])
        let extracted = workspace.appending(path: "out")
        _ = try run("/usr/bin/unzip", ["-q", archive.path, "-d", extracted.path])
        let folder = extracted.appending(path: "Safira-diagnostics-20261103-100000")
        #expect(try String(contentsOf: folder.appending(path: "environment.txt"), encoding: .utf8)
            == "Safira 0.1.0 (1)\nmacOS 27.1.0\n")
        let log = try String(contentsOf: folder.appending(path: logFile), encoding: .utf8)
        #expect(log.contains(" notice [navigation] page-loaded host=<private> ms=99\n"))
        let summary = try String(contentsOf: folder.appending(path: "summary.txt"), encoding: .utf8)
        #expect(summary.hasPrefix("Last error: "))
        #expect(summary.contains("load-failed host=- domain=WKErrorDomain code=7"))
        for text in [log, summary] {
            for forbidden in ["example.com", "secret-path", "q=1", "https"] {
                #expect(!text.contains(forbidden), "the export leaks \(forbidden)")
            }
        }
    }

    @Test func exportingReplacesAnEarlierArchive() async throws {
        let directory = makeLogsDirectory()
        let workspace = FileManager.default.temporaryDirectory.appending(path: "safira-export-\(UUID().uuidString)")
        defer { removeParent(of: directory); try? FileManager.default.removeItem(at: workspace) }
        let logger = makeLogger(in: directory, isEnabled: true)
        logger.record(.memory(footprintBytes: 1))
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let archive = workspace.appending(path: "diagnostics.zip")
        try Data("old".utf8).write(to: archive)

        try await logger.sink.export(environment: Self.environment, requireLogs: true, to: archive)

        #expect(try run("/usr/bin/unzip", ["-tq", archive.path]).contains("No errors"))
    }

    @Test func exportingWithoutLogsFailsInsteadOfWritingAnArchive() async throws {
        let directory = makeLogsDirectory()
        defer { removeParent(of: directory) }
        let destination = FileManager.default.temporaryDirectory.appending(path: "never-\(UUID().uuidString).zip")
        let logger = makeLogger(in: directory, isEnabled: false)

        await #expect(throws: DiagnosticArchiveError.noLogs) {
            try await logger.sink.export(environment: Self.environment, requireLogs: true, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func theEnvironmentNamesTheVersionsOnly() {
        #expect(Self.environment == "Safira 0.1.0 (1)\nmacOS 27.1.0")
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
}
