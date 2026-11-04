// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraWeb
import Testing

/// Removes a Profile's data store once its web views are released, for every real-WebKit suite.
/// WebKit refuses while a released web view's process still holds the store, so this retries for about 10 seconds.
/// Cleanup is not what a test proves: a store that still cannot be removed is recorded as a warning, never a failure.
@MainActor
func removeDataStoreWhenReleased(_ profile: ProfileID) async {
    var lastError: (any Error)?
    for _ in 0..<100 {
        do {
            try await ProfileWebContext.removeDataStore(of: profile)
            return
        } catch {
            lastError = error
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
    Issue.record("could not remove the data store of \(profile.rawValue): \(String(describing: lastError))",
                 severity: .warning)
}

/// Waits for a condition that WebKit makes true asynchronously, and records an issue when it never does.
@MainActor
func waitUntil(_ what: Comment, timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("timed out waiting until \(what)")
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}
