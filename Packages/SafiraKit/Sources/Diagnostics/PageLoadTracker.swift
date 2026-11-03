// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// Turns a web view's navigation callbacks into events. A load is timed from the commit to the finish, and the page
/// address is reduced to its host the moment it enters, so nothing downstream can see more.
public struct PageLoadTracker: Sendable {
    private var commit: (host: LoggedHost?, instant: ContinuousClock.Instant)?

    public init() {}

    public mutating func didCommit(url: URL?, at instant: ContinuousClock.Instant) {
        commit = (url.flatMap(LoggedHost.init), instant)
    }

    public mutating func didFinish(at instant: ContinuousClock.Instant) -> DiagnosticEvent? {
        defer { commit = nil }
        guard let commit else { return nil }
        let elapsed = commit.instant.duration(to: instant)
        let milliseconds = Int(elapsed.components.seconds) * 1000 + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        return .pageLoaded(host: commit.host, milliseconds: milliseconds)
    }

    /// - Parameter url: the address that failed to load.
    public mutating func didFail(url: URL?, error: any Error) -> DiagnosticEvent {
        commit = nil
        return .loadFailed(host: url.flatMap(LoggedHost.init), error: ErrorSummary(error))
    }
}
