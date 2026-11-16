// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// What the sidebar's downloads button shows of one Profile's downloads (or one Private window's).
public struct DownloadsIndicator: Hashable, Sendable {
    /// Shown while a download runs or is paused, or while a download of this run is still listed; hidden otherwise, so
    /// that the sidebar's footer stays quiet.
    public var isVisible: Bool
    public var runningCount: Int
    /// The combined progress of the running downloads whose size is known, between 0 and 1; nil when no size is known.
    public var fraction: Double?
    /// A download of this run failed and the list has not been opened since.
    public var needsAttention: Bool
    /// How many downloads finished during this run: each new one makes the button bounce.
    public var finishedCount: Int

    public init(isVisible: Bool, runningCount: Int = 0, fraction: Double? = nil, needsAttention: Bool = false,
                finishedCount: Int = 0) {
        self.isVisible = isVisible
        self.runningCount = runningCount
        self.fraction = fraction
        self.needsAttention = needsAttention
        self.finishedCount = finishedCount
    }

    public static let hidden = DownloadsIndicator(isVisible: false)

    /// - Parameters:
    ///   - startedThisRun: the downloads started or restarted since launch; the others come from an earlier run.
    ///   - unseenFailures: the downloads that failed since the list was last opened.
    public init(downloads: [DownloadRecord], startedThisRun: Set<DownloadID>, unseenFailures: Set<DownloadID>,
                finishedCount: Int) {
        let running = downloads.filter { $0.state == .active }
        let sized = running.compactMap { record in record.totalBytes.flatMap { $0 > 0 ? (record.receivedBytes, $0) : nil } }
        let total = sized.reduce(Int64(0)) { $0 + $1.1 }
        let received = sized.reduce(Int64(0)) { $0 + min($1.0, $1.1) }
        self.init(
            isVisible: downloads.contains { $0.state == .active || $0.state == .paused || startedThisRun.contains($0.id) },
            runningCount: running.count,
            fraction: total > 0 ? Double(received) / Double(total) : nil,
            needsAttention: downloads.contains { $0.state == .failed && unseenFailures.contains($0.id) },
            finishedCount: finishedCount)
    }

    /// The combined progress as a whole percentage, for VoiceOver and the help tag.
    public var percent: Int? {
        fraction.map { Int(($0 * 100).rounded(.down)) }
    }
}

/// Estimates the time a transfer has left from the bytes received since it was first measured in this run.
public struct TransferRate: Hashable, Sendable {
    public let startBytes: Int64
    public let startTime: Date

    public init(startBytes: Int64, startTime: Date) {
        self.startBytes = startBytes
        self.startTime = startTime
    }

    /// Nil until at least a second has passed and some bytes arrived, and when the size is unknown.
    public func timeRemaining(received: Int64, total: Int64?, at now: Date) -> TimeInterval? {
        guard let total, total > received else { return total == received ? 0 : nil }
        let elapsed = now.timeIntervalSince(startTime)
        let gained = received - startBytes
        guard elapsed >= 1, gained > 0 else { return nil }
        return Double(total - received) / (Double(gained) / elapsed)
    }
}
