// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import SafiraWeb
import Testing
import WebKit

@MainActor
@Suite struct IsolationTests {
    @Test func eachProfileGetsTheDataStoreNamedByItsOwnUUID() async throws {
        let work = try #require(ProfileID(uuidString: "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A"))
        let personal = try #require(ProfileID(uuidString: "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F"))

        do {
            let workContext = ProfileWebContext(profileID: work)
            let personalContext = ProfileWebContext(profileID: personal)

            #expect(workContext.makeConfiguration().websiteDataStore.identifier?.uuidString
                == "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A")
            #expect(personalContext.makeConfiguration().websiteDataStore.identifier?.uuidString
                == "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F")
            #expect(workContext.makeConfiguration().websiteDataStore === workContext.dataStore)
        }

        try await ProfileWebContext.removeDataStore(of: work)
        try await ProfileWebContext.removeDataStore(of: personal)
    }
}
