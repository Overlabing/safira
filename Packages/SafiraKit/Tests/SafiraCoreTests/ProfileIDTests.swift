// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

@Test func profileIDParsesAUUIDString() {
    let id = ProfileID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")
    #expect(id?.rawValue.uuidString == "6F9619FF-8B86-D011-B42D-00C04FC964FF")
}

@Test func profileIDRejectsAStringThatIsNotAUUID() {
    #expect(ProfileID(uuidString: "work") == nil)
}
