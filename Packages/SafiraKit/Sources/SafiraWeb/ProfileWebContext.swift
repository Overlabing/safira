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
    /// Read each time a page is built: a change reaches the pages created after it, never the ones already open.
    public var webContentSettings: WebContentSettings
    /// The live pages of this Profile's Tabs. They live here, outside the views, until their Tab closes.
    private var pages: [TabID: WebKitPage] = [:]

    public init(profileID: ProfileID, webContentSettings: WebContentSettings = WebContentSettings()) {
        self.profileID = profileID
        self.webContentSettings = webContentSettings
        self.dataStore = WKWebsiteDataStore(forIdentifier: profileID.rawValue)
    }

    public func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        // Explicit, so hidden Tabs do not depend on the default linked to the SDK version (architecture §4.1).
        configuration.preferences.inactiveSchedulingPolicy = .suspend
        configuration.preferences.isFraudulentWebsiteWarningEnabled = webContentSettings.isFraudulentSiteWarningEnabled
        configuration.mediaTypesRequiringUserActionForPlayback = webContentSettings.isAutoplayingSoundAllowed ? [] : .audio
        return configuration
    }

    /// Builds the page of a Tab with this Profile's configuration. It stays registered until it is closed.
    public func makePage(for tabID: TabID) -> WebKitPage {
        let page = WebKitPage(configuration: makeConfiguration()) { [weak self] in
            self?.pages[tabID] = nil
        }
        pages[tabID] = page
        return page
    }

    public func webView(for tabID: TabID) -> WKWebView? {
        pages[tabID]?.webView
    }

    public static func removeDataStore(of profileID: ProfileID) async throws {
        try await WKWebsiteDataStore.remove(forIdentifier: profileID.rawValue)
    }
}
