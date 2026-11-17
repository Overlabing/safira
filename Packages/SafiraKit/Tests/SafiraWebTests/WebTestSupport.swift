// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraWeb
import TestSupport
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

/// Waits for a condition that WebKit makes true asynchronously, and records an issue when it never does within the
/// shared deadline.
@MainActor
func waitUntil(_ what: Comment, _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + TestDeadline.external
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("timed out waiting until \(what)")
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// `waitUntil` for a condition that has to be read asynchronously, such as the cookies WebKit has persisted.
/// A page script's `document.cookie` write reaches the data store a moment later, so read it through this and not at once.
@MainActor
func waitUntilAsync(_ what: Comment, _ condition: () async -> Bool) async throws {
    let deadline = ContinuousClock.now + TestDeadline.external
    while await !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("timed out waiting until \(what)")
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

/// Keeps the main thread busy, as a loaded machine does, until `condition` holds and `margin` more has passed, for at
/// most the shared deadline. WebKit's messages to the app queue up meanwhile and are then handled one after another,
/// before any main-actor work an `await` resumed in between.
@MainActor
func holdMainThread(until condition: () -> Bool = { true }, margin: Duration) {
    let deadline = ContinuousClock.now + TestDeadline.external
    while !condition(), ContinuousClock.now < deadline { usleep(10_000) }
    let end = min(ContinuousClock.now + margin, deadline)
    while ContinuousClock.now < end { usleep(10_000) }
}

/// Runs the tests of every suite that carries it one at a time, across suites. `.serialized` orders the tests of one
/// suite only, so without this every real-WebKit suite runs at once: dozens of web content and network processes on a
/// CI runner's three cores, and a test that holds the main thread (`holdMainThread`) stalls every other test's wait.
struct OneWebKitTestAtATime: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func scopeProvider(for test: Test, testCase: Test.Case?) -> Self? {
        testCase == nil ? nil : self
    }

    func provideScope(for test: Test, testCase: Test.Case?,
                      performing function: @Sendable () async throws -> Void) async throws {
        await WebKitTurns.shared.take()
        do {
            try await function()
        } catch {
            await WebKitTurns.shared.giveBack()
            throw error
        }
        await WebKitTurns.shared.giveBack()
    }
}

extension Trait where Self == OneWebKitTestAtATime {
    static var oneWebKitTestAtATime: Self { Self() }
}

/// A first-come, first-served turn shared by every suite with `.oneWebKitTestAtATime`.
private actor WebKitTurns {
    static let shared = WebKitTurns()
    private var taken = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func take() async {
        guard taken else {
            taken = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func giveBack() {
        if waiting.isEmpty {
            taken = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}
