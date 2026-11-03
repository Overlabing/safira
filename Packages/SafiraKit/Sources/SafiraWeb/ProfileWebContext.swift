// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import WebKit

/// The only owner of a Profile's website data store, and the only place that builds web view configurations.
/// This file is the one place allowed to name website data stores (scripts/guard-singletons.sh).
@MainActor
public final class ProfileWebContext {
    public let profileID: ProfileID
    public let dataStore: WKWebsiteDataStore

    public init(profileID: ProfileID) {
        self.profileID = profileID
        self.dataStore = WKWebsiteDataStore(forIdentifier: profileID.rawValue)
    }

    public func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        return configuration
    }

    public static func removeDataStore(of profileID: ProfileID) async throws {
        try await WKWebsiteDataStore.remove(forIdentifier: profileID.rawValue)
    }
}
