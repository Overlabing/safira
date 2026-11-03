// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// How much Debug mode may keep on disk.
public struct LogLimits: Hashable, Sendable {
    public var maxFileBytes: Int
    public var maxAge: Duration
    /// Should be at least `maxFileBytes`: the file being written is never pruned for size alone.
    public var maxTotalBytes: Int

    public init(maxFileBytes: Int, maxAge: Duration, maxTotalBytes: Int) {
        self.maxFileBytes = maxFileBytes
        self.maxAge = maxAge
        self.maxTotalBytes = maxTotalBytes
    }

    public static let standard = LogLimits(maxFileBytes: 5_000_000, maxAge: .seconds(7 * 24 * 3600),
                                           maxTotalBytes: 25_000_000)
}

/// Rotating log files in one folder. The folder is created by the first line written, never before.
struct LogFileStore: Sendable {
    static let fileExtension = "log"

    let directory: URL
    let limits: LogLimits
    private var current: (url: URL, size: Int)?
    private var lastPrune: Date?

    init(directory: URL, limits: LogLimits) {
        self.directory = directory
        self.limits = limits
    }

    mutating func append(_ text: String, at now: Date) throws {
        let data = Data(text.utf8)
        let fileManager = FileManager.default
        if current == nil {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            prune(at: now)
            current = Self.newestFile(in: directory)
        } else if let lastPrune, now.timeIntervalSince(lastPrune) > 3600 {
            prune(at: now)
        }
        if let existing = current, existing.size > 0, existing.size + data.count > limits.maxFileBytes {
            current = nil
        }
        if let existing = current, !fileManager.fileExists(atPath: existing.url.path) {
            current = nil
        }
        let target = current ?? (uniqueFileURL(at: now), 0)
        if !fileManager.fileExists(atPath: target.url.path) {
            fileManager.createFile(atPath: target.url.path, contents: nil)
        }
        current = target
        let handle = try FileHandle(forWritingTo: target.url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        current = (target.url, target.size + data.count)
        if target.size == 0 {
            // A new file is the moment the total can first exceed its limit.
            prune(at: now)
        }
    }

    static func logFiles(in directory: URL) -> [(url: URL, size: Int, modified: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls.filter { $0.pathExtension == fileExtension }.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)), let size = values.fileSize,
                  let modified = values.contentModificationDate else { return nil }
            return (url, size, modified)
        }
        .sorted { ($0.modified, $0.url.lastPathComponent) < ($1.modified, $1.url.lastPathComponent) }
    }

    private static func newestFile(in directory: URL) -> (url: URL, size: Int)? {
        logFiles(in: directory).last.map { ($0.url, $0.size) }
    }

    /// Deletes files older than the age limit, then the oldest files until the total fits.
    private mutating func prune(at now: Date) {
        lastPrune = now
        let fileManager = FileManager.default
        let cutoff = now.addingTimeInterval(-limits.maxAge.timeInterval)
        var files = Self.logFiles(in: directory)
        for file in files where file.modified < cutoff {
            try? fileManager.removeItem(at: file.url)
        }
        files.removeAll { $0.modified < cutoff }
        var total = files.reduce(0) { $0 + $1.size }
        for file in files where total > limits.maxTotalBytes && file.url != current?.url {
            try? fileManager.removeItem(at: file.url)
            total -= file.size
        }
    }

    private func uniqueFileURL(at date: Date) -> URL {
        let stamp = date.formatted(Self.fileNameStyle)
        var url = directory.appending(path: "safira-\(stamp).\(Self.fileExtension)", directoryHint: .notDirectory)
        var suffix = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appending(path: "safira-\(stamp)-\(suffix).\(Self.fileExtension)", directoryHint: .notDirectory)
            suffix += 1
        }
        return url
    }

    private static let fileNameStyle = Date.ISO8601FormatStyle(dateSeparator: .omitted, timeSeparator: .omitted,
                                                       includingFractionalSeconds: true, timeZone: .gmt)
}

extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
