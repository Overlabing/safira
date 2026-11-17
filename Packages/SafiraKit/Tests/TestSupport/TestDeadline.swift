// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// The one deadline for a wait on something a test cannot schedule: WebKit's processes, a page load, a process the test
/// starts. A wait ends as soon as the awaited event happens, so the deadline only bounds a failure; it is long because
/// the first web content, network or host process started on a cold CI runner takes several seconds.
public enum TestDeadline {
    public static let external: Duration = .seconds(30)
}
