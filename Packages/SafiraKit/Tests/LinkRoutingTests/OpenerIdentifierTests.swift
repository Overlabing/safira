// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import LinkRouting
import Testing

/// Answers for fixed process identifiers, as the system would, without asking LaunchServices.
private struct FixedApplications: RunningApplicationLookup {
    let applications: [Int32: Opener]

    func application(processIdentifier: Int32) -> Opener? {
        applications[processIdentifier]
    }
}

private let slack = Opener(bundleIdentifier: "com.tinyspeck.slackmacgap", name: "Slack")
private let identifier = OpenerIdentifier(
    lookup: FixedApplications(applications: [
        4242: slack,
        77: Opener(bundleIdentifier: nil, name: nil),
        500: Opener(bundleIdentifier: nil, name: "Helper"),
        900: Opener(bundleIdentifier: "com.overlabing.safira", name: "Safira"),
    ]),
    ownProcessIdentifier: 900
)

@Test func theSenderOfTheOpenEventIsTheOpener() {
    #expect(identifier.identify(senderProcessIdentifier: 4242) == slack)
}

@Test func anAppWithOnlyANameIsStillAnOpener() {
    #expect(identifier.identify(senderProcessIdentifier: 500) == Opener(bundleIdentifier: nil, name: "Helper"))
}

@Test(arguments: [nil, 0, -1, 31337, 77, 900] as [Int32?])
func thereIsNoOpenerWhenTheSenderIsUnknownNotAnAppOrSafiraItself(sender: Int32?) {
    #expect(identifier.identify(senderProcessIdentifier: sender) == nil)
}
