// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Synchronization
import Testing

/// Two suites that Swift Testing would run side by side: with `.oneWebKitTestAtATime`, no test of one overlaps a test
/// of the other.
private let running = Mutex(0)

private func occupy() async throws {
    let alongside = running.withLock { count in
        count += 1
        return count - 1
    }
    try await Task.sleep(for: .milliseconds(100))
    running.withLock { $0 -= 1 }
    #expect(alongside == 0)
}

@Suite(.oneWebKitTestAtATime) struct OneWebKitTestAtATimeFirstTests {
    @Test(arguments: 0..<4) func aTestRunsAlone(_ index: Int) async throws { try await occupy() }
}

@Suite(.oneWebKitTestAtATime) struct OneWebKitTestAtATimeSecondTests {
    @Test(arguments: 0..<4) func aTestRunsAlone(_ index: Int) async throws { try await occupy() }
}
