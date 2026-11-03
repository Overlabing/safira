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
    private let mediaEvents = MediaEventHandler()

    public init(profileID: ProfileID, webContentSettings: WebContentSettings = WebContentSettings()) {
        self.profileID = profileID
        self.webContentSettings = webContentSettings
        self.dataStore = WKWebsiteDataStore(forIdentifier: profileID.rawValue)
        mediaEvents.context = self
    }

    public func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        // Explicit, so hidden Tabs do not depend on the default linked to the SDK version (architecture §4.1).
        configuration.preferences.inactiveSchedulingPolicy = .suspend
        mediaEvents.install(in: configuration.userContentController)
        configuration.preferences.isFraudulentWebsiteWarningEnabled = webContentSettings.isFraudulentSiteWarningEnabled
        configuration.mediaTypesRequiringUserActionForPlayback = webContentSettings.isAutoplayingSoundAllowed ? [] : .audio
        return configuration
    }

    /// Builds the page of a Tab with this Profile's configuration. It stays registered until it is closed.
    public func makePage(for tabID: TabID) -> WebKitPage {
        register(tabID, configuration: makeConfiguration())
    }

    public func webView(for tabID: TabID) -> WKWebView? {
        pages[tabID]?.webView
    }

    public static func removeDataStore(of profileID: ProfileID) async throws {
        try await WKWebsiteDataStore.remove(forIdentifier: profileID.rawValue)
    }

    /// `configuration` is either this Profile's or the copy WebKit hands over for a `target=_blank` link, which
    /// WebKit derives from the opener's, so both use this Profile's data store.
    private func register(_ tabID: TabID, configuration: WKWebViewConfiguration) -> WebKitPage {
        let page = WebKitPage(
            configuration: configuration,
            makeNewTabPage: { [weak self] configuration in
                guard let self else { return nil }
                let id = TabID()
                return (id, register(id, configuration: configuration))
            },
            onClose: { [weak self] in self?.unregister(tabID) }
        )
        pages[tabID] = page
        return page
    }

    private func unregister(_ tabID: TabID) {
        guard let page = pages.removeValue(forKey: tabID) else { return }
        // A `target=_blank` page shares its opener's content controller; its handlers go with the last page using it.
        let controller = page.webView.configuration.userContentController
        let shared = pages.values.contains { $0.webView.configuration.userContentController === controller }
        if !shared {
            controller.removeAllScriptMessageHandlers()
        }
    }

    fileprivate func page(showing webView: WKWebView?) -> WebKitPage? {
        pages.values.first { $0.webView === webView }
    }
}

/// Tells a page to ask WebKit for its media playback state whenever a media element starts or stops. The script runs
/// in its own content world, out of the page's reach, and sends no data.
@MainActor
private final class MediaEventHandler: NSObject, WKScriptMessageHandler {
    weak var context: ProfileWebContext?
    private static let world = WKContentWorld.world(name: "Safira")
    private static let name = "media"
    private static let script = WKUserScript(
        source: """
        for (const type of ["play", "playing", "pause", "ended", "emptied"]) {
            document.addEventListener(type, () => window.webkit.messageHandlers.media.postMessage(null), true);
        }
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false,
        in: world
    )

    func install(in controller: WKUserContentController) {
        controller.addUserScript(Self.script)
        controller.add(self, contentWorld: Self.world, name: Self.name)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        context?.page(showing: message.webView)?.refreshMediaState()
    }
}
