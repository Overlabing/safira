// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Preferences
import SafiraCore
import Testing
import UserFacing

/// A defaults domain of its own, never Safira's real one; the caller removes it.
func scratchDefaults() throws -> (UserDefaults, domain: String) {
    let domain = "safira-test-\(UUID().uuidString)"
    return (try #require(UserDefaults(suiteName: domain)), domain)
}

private let flag = LegacyPreference(key: "test.flag", as: Bool.self) { LegacyPreference.bool($0) }

@Suite struct LegacyPreferenceTests {
    @Test func aPlainValueBecomesTheJSONThePreferenceReads() throws {
        let (defaults, domain) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(true, forKey: "test.flag")

        LegacyPreference.migrate([flag], in: defaults, domain: domain)

        #expect(defaults.data(forKey: "test.flag") == Data("true".utf8))
        #expect(try Preference(key: "test.flag", defaultValue: false, store: defaults).load() == true)
    }

    @Test func aValueAlreadyMigratedIsLeftAlone() throws {
        let (defaults, domain) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        try Preference(key: "test.flag", defaultValue: false, store: defaults).save(false)

        LegacyPreference.migrate([flag], in: defaults, domain: domain)
        LegacyPreference.migrate([flag], in: defaults, domain: domain)

        #expect(defaults.data(forKey: "test.flag") == Data("false".utf8))
    }

    @Test func anOldValueTheOldStoreCouldNotReadIsDroppedSoTheDefaultApplies() throws {
        let (defaults, domain) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(["not", "a", "flag"], forKey: "test.flag")

        LegacyPreference.migrate([flag], in: defaults, domain: domain)

        #expect(defaults.persistentDomain(forName: domain)?.keys.contains("test.flag") == false)
    }

    @Test func aValueOutsideThePersistentDomainIsNeverWritten() throws {
        let (defaults, domain) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.register(defaults: ["test.flag": true])

        LegacyPreference.migrate([flag], in: defaults, domain: domain)

        #expect(defaults.persistentDomain(forName: domain)?.keys.contains("test.flag") != true)
    }

    @Test func booleansReadAsUserDefaultsReadThem() {
        #expect(LegacyPreference.bool(NSNumber(value: true)) == true)
        #expect(LegacyPreference.bool(NSNumber(value: 0)) == false)
        #expect(LegacyPreference.bool("YES") == true)
        #expect(LegacyPreference.bool("false") == false)
        #expect(LegacyPreference.bool("1") == true)
        #expect(LegacyPreference.bool("maybe") == nil)
        #expect(LegacyPreference.bool(Data()) == nil)
    }
}

@Suite struct RestoringDefaultTests {
    @Test func anUnreadableValueGivesTheDefaultIsReplacedOnDiskAndIsReportedOnce() throws {
        let store = InMemoryKeyValueStore()
        store.setData(Data("not json".utf8), forKey: "test.count")
        let preference = Preference(key: "test.count", defaultValue: 3, store: store)
        var problems: [PreferenceError] = []

        #expect(preference.loadRestoringDefault { problems.append($0) } == 3)
        #expect(preference.loadRestoringDefault { problems.append($0) } == 3)

        #expect(problems == [.unreadable(key: "test.count")])
        #expect(try preference.load() == 3)
    }

    /// The message is AppSupportKit's sentence: scripts/check.sh pins the kit's language with OVERLABING_TEST_LANGUAGE=en.
    @Test func theUserIsToldInABannerThatTheDefaultsAreBack() {
        let error = PreferenceError.unreadable(key: "test.count").userFacingError

        #expect(error.presentation == .banner)
        #expect(error.message == "The saved settings couldn't be read, so the defaults have been restored.")
        #expect(error.action == nil)
    }
}
