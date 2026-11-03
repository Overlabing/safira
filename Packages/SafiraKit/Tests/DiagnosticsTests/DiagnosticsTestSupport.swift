// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation

/// A throwaway folder that does not exist until a test or the logger creates it.
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

func url(_ string: String) -> URL {
    URL(string: string)!
}
