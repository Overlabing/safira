// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraWeb
import Testing

/// WebKit refuses to remove a data store while a released web view's process still holds it; that takes a moment.
@MainActor
func removeDataStoreWhenReleased(_ profile: ProfileID) async throws {
    for _ in 1..<50 {
        do {
            return try await ProfileWebContext.removeDataStore(of: profile)
        } catch {
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    try await ProfileWebContext.removeDataStore(of: profile)
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
