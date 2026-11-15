// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore
import SafiraSession
import WebKit

/// An extension loaded into a Profile, as the Profile's host reports it.
public struct LoadedExtension: Hashable, Sendable {
    /// `browser.runtime.id`: derived from the manifest `key` when there is one, so it stays the same at every load.
    public let identifier: String
    public let displayName: String
    public let version: String
    /// What WebKit reported while reading and loading the extension; empty when it had nothing to say.
    public let errors: [String]
}

/// The web extensions of one Profile: one `WKWebExtensionController` whose extensions read and write only that
/// Profile's website data store, and the Tabs and window they see, which are that Profile's own. A Private window has
/// no host, so no extension runs in it. Nothing loaded here is remembered after a relaunch.
@MainActor
public final class ExtensionHost: NSObject {
    let controller: WKWebExtensionController
    private unowned let web: ProfileWebContext
    private weak var session: ProfileSession?
    private lazy var window = ExtensionWindow(host: self)
    /// The Tabs whose page exists, which is what an extension can reach; a Tab not shown since launch has none yet.
    private var tabs: [TabID: ExtensionTab] = [:]
    /// The Tab last reported to the controller as active, so that each change is reported once.
    private var activeTabID: TabID?

    init(web: ProfileWebContext, storage: WebsiteStorage) {
        self.web = web
        let configuration: WKWebExtensionController.Configuration = switch storage {
        case .onDisk: WKWebExtensionController.Configuration(identifier: web.profileID.rawValue)
        case .inMemory: WKWebExtensionController.Configuration.nonPersistent()
        }
        // The default is the app's default data store, which every Profile would share (architecture §2.2 rule 6).
        configuration.defaultWebsiteDataStore = web.dataStore
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
    }

    /// The extensions loaded into this Profile.
    public var loadedExtensions: [LoadedExtension] {
        controller.extensionContexts.map(Self.summary).sorted { $0.displayName < $1.displayName }
    }

    /// Loads an unpacked extension (a folder holding its `manifest.json`) into this Profile, granting everything its
    /// manifest asks for: only the Debug mode command loads one, and asking first is a later unit. The pages opened
    /// before keep running without it; it reaches the pages created from now on.
    @discardableResult
    public func loadUnpacked(at folder: URL) async throws -> LoadedExtension {
        let webExtension = try await WKWebExtension(resourceBaseURL: folder)
        let context = WKWebExtensionContext(for: webExtension)
        let identifier = ExtensionIdentity.identifier(forManifest: webExtension.manifest)
        context.uniqueIdentifier = identifier
        if let base = URL(string: "webkit-extension://\(identifier)/") {
            context.baseURL = base
        }
        // Public API: the extension's pages and service worker show in Safari's Develop menu (ADR 0001).
        context.isInspectable = true
        for permission in webExtension.requestedPermissions {
            context.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        for pattern in webExtension.allRequestedMatchPatterns {
            context.setPermissionStatus(.grantedExplicitly, for: pattern)
        }
        try controller.load(context)
        return Self.summary(context)
    }

    // MARK: The Profile's Tabs

    /// Starts following the session's selection, which `didActivateTab` reports.
    func attach(to session: ProfileSession) {
        self.session = session
        followSelection()
    }

    func pageOpened(_ id: TabID) {
        guard tabs[id] == nil else { return }
        let tab = ExtensionTab(id: id, host: self)
        tabs[id] = tab
        controller.didOpenTab(tab)
        reportSelection()
    }

    func pageClosed(_ id: TabID) {
        guard let tab = tabs.removeValue(forKey: id) else { return }
        if activeTabID == id { activeTabID = nil }
        controller.didCloseTab(tab, windowIsClosing: false)
    }

    private func followSelection() {
        withObservationTracking {
            _ = session?.selectedTabID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.reportSelection()
                self?.followSelection()
            }
        }
    }

    private func reportSelection() {
        guard let selected = session?.selectedTabID, selected != activeTabID, let tab = tabs[selected] else { return }
        let previous = activeTabID.flatMap { tabs[$0] }
        activeTabID = selected
        controller.didActivateTab(tab, previousActiveTab: previous)
    }

    // MARK: What the adapters read

    /// The Tabs with a page, in sidebar order: Space by Space, Pinned tabs first.
    var openTabs: [ExtensionTab] {
        let order = session?.spaces.flatMap(\.allTabs).map(\.id) ?? []
        let ordered = order.compactMap { tabs[$0] }
        // A page a link opened is announced before the session lists its Tab.
        return ordered + tabs.values.filter { !order.contains($0.id) }
    }

    var activeTab: ExtensionTab? {
        activeTabID.flatMap { tabs[$0] }
    }

    var extensionWindow: ExtensionWindow { window }

    func webView(for id: TabID) -> WKWebView? {
        web.webView(for: id)
    }

    func sessionTab(_ id: TabID) -> Tab? {
        session?.spaces.lazy.flatMap(\.allTabs).first { $0.id == id }
    }

    func select(_ id: TabID) {
        session?.select(id)
    }

    func close(_ id: TabID) {
        session?.close(id)
    }

    private static func summary(_ context: WKWebExtensionContext) -> LoadedExtension {
        let webExtension = context.webExtension
        return LoadedExtension(identifier: context.uniqueIdentifier,
                               displayName: webExtension.displayName ?? "",
                               version: webExtension.version ?? "",
                               errors: context.errors.map(\.localizedDescription))
    }
}

extension ExtensionHost: WKWebExtensionControllerDelegate {
    public func webExtensionController(_ controller: WKWebExtensionController,
                                       openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        [window]
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        window
    }
}

/// Where a Profile keeps its website data and its extensions' state. Tests use `.inMemory`, which writes nothing.
enum WebsiteStorage {
    case onDisk
    case inMemory
}
