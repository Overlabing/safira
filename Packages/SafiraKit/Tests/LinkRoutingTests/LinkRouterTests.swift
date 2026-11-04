// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import SafiraCore
import Testing

let workProfile = Profile(id: ProfileID(uuidString: "11111111-1111-4111-8111-111111111111")!, name: "Work", symbol: "💼")
let homeProfile = Profile(id: ProfileID(uuidString: "22222222-2222-4222-8222-222222222222")!, name: "Home", symbol: "🏡")
let exampleLink = IncomingLink(url: URL(string: "https://example.com/a/path?q=secret#frag")!)

@Test func aSingleProfileReceivesTheLinkWithoutAsking() {
    #expect(LinkRouter.decide(for: exampleLink, among: [workProfile]) == .open(workProfile.id))
}

@Test func severalProfilesMeanTheUserChooses() {
    #expect(LinkRouter.decide(for: exampleLink, among: [workProfile, homeProfile]) == .ask)
}
