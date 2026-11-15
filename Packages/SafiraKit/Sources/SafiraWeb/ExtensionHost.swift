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

    /// The extensions' actions for the active Tab, which the sidebar shows as buttons.
    public let actions = ExtensionActions()
    /// Shows an action's popup; set by the window that shows the actions' buttons.
    public var popupPresenter: ExtensionPopupPresenter?

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
        refreshActions()
        return Self.summary(context)
    }

    // MARK: Actions

    /// Does what a click on the extension's button does, for the active Tab: runs `action.onClicked` in the
    /// extension, or opens its popup through `popupPresenter`. It also grants `activeTab` for that Tab.
    public func performAction(extensionID: String) {
        guard let context = context(extensionID) else { return }
        context.performAction(for: activeTab)
    }

    /// Reads every action again for the active Tab: after a load, a change of Tab, or the extension's own change.
    func refreshActions() {
        let side = ExtensionActions.iconSide
        let items = controller.extensionContexts
            .sorted { ($0.webExtension.displayName ?? "") < ($1.webExtension.displayName ?? "") }
            .compactMap { context -> ExtensionActionItem? in
                guard Self.hasAction(context.webExtension), let action = context.action(for: activeTab) else { return nil }
                let name = context.webExtension.displayName ?? ""
                return ExtensionActionItem(id: context.uniqueIdentifier, name: name,
                                           label: action.label.isEmpty ? name : action.label,
                                           badgeText: action.badgeText, isEnabled: action.isEnabled,
                                           icon: action.icon(for: CGSize(width: side, height: side)))
            }
        actions.update(items)
    }

    /// WebKit gives every extension a default action; only one whose manifest declares it shows a button.
    private static func hasAction(_ webExtension: WKWebExtension) -> Bool {
        ["action", "browser_action", "page_action"].contains { webExtension.manifest[$0] != nil }
    }

    private func context(_ extensionID: String) -> WKWebExtensionContext? {
        controller.extensionContexts.first { $0.uniqueIdentifier == extensionID }
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
        refreshActions()
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
        refreshActions()
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

    public func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action,
                                       forExtensionContext context: WKWebExtensionContext) {
        refreshActions()
    }

    /// Called once the popup's page has loaded, for a click and for `action.openPopup()` alike.
    public func webExtensionController(_ controller: WKWebExtensionController,
                                       presentActionPopup action: WKWebExtension.Action,
                                       for context: WKWebExtensionContext,
                                       completionHandler: @escaping ((any Error)?) -> Void) {
        guard let popupPresenter else { return completionHandler(ExtensionPopupUnavailable()) }
        do {
            try popupPresenter(context.uniqueIdentifier, action)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}

/// Where a Profile keeps its website data and its extensions' state. Tests use `.inMemory`, which writes nothing.
enum WebsiteStorage {
    case onDisk
    case inMemory
}
