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
/// no host, so no extension runs in it. What it loads comes from the app's extension library, which remembers it.
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

    /// `runtime.connectNative` and `sendNativeMessage`, to the native messaging hosts apps register (ADR 0007).
    public var nativeMessaging = NativeMessaging()

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
        errorObserver = NotificationCenter.default.addObserver(forName: WKWebExtensionContext.errorsDidUpdateNotification,
                                                               object: nil, queue: .main) { [weak self] note in
            let context = note.object as? WKWebExtensionContext
            MainActor.assumeIsolated { self?.errorsChanged(in: context) }
        }
    }

    isolated deinit {
        if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
    }

    private var errorObserver: (any NSObjectProtocol)?

    /// Told why an extension's service worker or background page could not start in this Profile, or nil once it
    /// reports no such failure; set by the app's extension library.
    var backgroundFailures: (@MainActor (_ extensionID: String, _ reason: String?) -> Void)?

    private func errorsChanged(in context: WKWebExtensionContext?) {
        guard let context, context.webExtensionController === controller else { return }
        backgroundFailures?(context.uniqueIdentifier, Self.backgroundFailure(in: context.errors))
    }

    /// Why the background failed to start, when WebKit reports that it did. The failure's own text names no cause:
    /// WebKit records the worker's uncaught exception, with its source location, just before it, or, when the worker
    /// could not even begin, a script error just after it.
    static func backgroundFailure(in errors: [any Error]) -> String? {
        let errors = errors.map { $0 as NSError }.filter { $0.domain == WKWebExtensionContext.errorDomain }
        let failed = WKWebExtensionContext.Error.backgroundContentFailedToLoad.rawValue
        guard let index = errors.firstIndex(where: { $0.code == failed }) else { return nil }
        let cause = errors[..<index].last ?? errors[(index + 1)...].first { $0.code != failed }
        return (cause ?? errors[index]).localizedDescription
    }

    /// The extensions loaded into this Profile.
    public var loadedExtensions: [LoadedExtension] {
        controller.extensionContexts.map(Self.summary).sorted { $0.displayName < $1.displayName }
    }

    /// Asks the user about what an extension asks for at run time, and remembers the answer for every Profile; set by
    /// the app's extension library. Without it such requests are refused.
    var permissionRequests: (@MainActor (ExtensionPermissionRequest) async -> Bool)?

    /// Loads an installed extension from `resource`, its folder or its ZIP copy, under the identifier fixed at install,
    /// with what the user allowed. The pages opened before keep running without it; it reaches the pages created from
    /// now on. An extension already loaded here is left as it is.
    @discardableResult
    func load(_ installed: InstalledExtension, from resource: URL) async throws -> LoadedExtension {
        // WebKit reads only the relative part of a URL that has a base, such as `Bundle.resourceURL` and anything
        // appended to it, and kills the app on the invalid address that leaves (a `RELEASE_ASSERT`, not an error).
        guard resource.isFileURL else { throw ExtensionFolderUnreadable(folder: resource) }
        let resource = resource.absoluteURL.standardizedFileURL
        let webExtension = try await WKWebExtension(resourceBaseURL: resource)
        if let loaded = context(installed.id) { return Self.summary(loaded) }
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = installed.id
        if let base = URL(string: "webkit-extension://\(installed.id)/") {
            context.baseURL = base
        }
        // Public API: the extension's pages and service worker show in Safari's Develop menu (ADR 0001).
        context.isInspectable = true
        grant(InstalledGrants(permissions: Set(installed.grantedPermissions),
                              matchPatterns: Set(installed.grantedMatchPatterns)), to: context)
        try controller.load(context)
        refreshActions()
        return Self.summary(context)
    }

    /// Stops an extension in this Profile: its content scripts no longer reach new pages and its service worker
    /// stops. What it stored stays.
    func unload(_ extensionID: String) {
        guard let context = context(extensionID) else { return }
        try? controller.unload(context)
        refreshActions()
    }

    /// Gives a loaded extension what the user allowed since it was loaded.
    func grant(_ grants: InstalledGrants, to extensionID: String) {
        guard let context = context(extensionID) else { return }
        grant(grants, to: context)
    }

    private func grant(_ grants: InstalledGrants, to context: WKWebExtensionContext) {
        for permission in grants.permissions {
            context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(rawValue: permission))
        }
        for pattern in grants.matchPatterns {
            if let matchPattern = try? WKWebExtension.MatchPattern(string: pattern) {
                context.setPermissionStatus(.grantedExplicitly, for: matchPattern)
            }
        }
    }

    /// Deletes what the extension stored in this Profile (`storage.local`, `storage.session`, `storage.sync`).
    func removeData(of extensionID: String) async {
        await Self.removeData(of: extensionID, from: controller)
    }

    /// Deletes what an extension stored in a Profile whose host does not exist in this run, through a controller of
    /// the same identifier that loads nothing.
    static func removeData(of extensionID: String, inProfile profileID: ProfileID) async {
        let configuration = WKWebExtensionController.Configuration(identifier: profileID.rawValue)
        // Never the app's default data store, which every Profile would share; nothing is loaded into this one.
        configuration.defaultWebsiteDataStore = .nonPersistent()
        await removeData(of: extensionID, from: WKWebExtensionController(configuration: configuration))
    }

    static func removeData(of extensionID: String, from controller: WKWebExtensionController) async {
        let types: Set<WKWebExtension.DataType> = [.local, .session, .synchronized]
        let records = await controller.dataRecords(ofTypes: types).filter { $0.uniqueIdentifier == extensionID }
        guard !records.isEmpty else { return }
        await withCheckedContinuation { done in
            controller.removeData(ofTypes: types, from: records) { done.resume() }
        }
    }

    /// What a web view needs to show one of the extension's own pages: WebKit loads them only in this configuration,
    /// not in a Tab's.
    public func webViewConfiguration(forExtension extensionID: String) -> WKWebViewConfiguration? {
        context(extensionID)?.webViewConfiguration
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

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       connectUsing port: WKWebExtension.MessagePort,
                                       for extensionContext: WKWebExtensionContext,
                                       completionHandler: @escaping ((any Error)?) -> Void) {
        do {
            try nativeMessaging.connect(WebKitMessagePort(port), extensionIdentifier: extensionContext.uniqueIdentifier)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    public func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any,
                                       toApplicationWithIdentifier applicationIdentifier: String?,
                                       for extensionContext: WKWebExtensionContext,
                                       replyHandler: @escaping (Any?, (any Error)?) -> Void) {
        let extensionIdentifier = extensionContext.uniqueIdentifier
        Task {
            do {
                let reply = try await nativeMessaging.sendMessage(message, applicationIdentifier: applicationIdentifier,
                                                                  extensionIdentifier: extensionIdentifier)
                replyHandler(reply, nil)
            } catch {
                replyHandler(nil, error)
            }
        }
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                       in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                       completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let request = runtimeRequest(extensionContext, permissions: permissions.map(\.rawValue), matchPatterns: [])
        Task {
            completionHandler(await ask(request) ? permissions : [], nil)
        }
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                       in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                       completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        let request = runtimeRequest(extensionContext, permissions: [], matchPatterns: matchPatterns.map(\.string),
                                     allHosts: matchPatterns.contains { $0.matchesAllHosts || $0.matchesAllURLs })
        Task {
            completionHandler(await ask(request) ? matchPatterns : [], nil)
        }
    }

    public func webExtensionController(_ controller: WKWebExtensionController,
                                       promptForPermissionToAccess urls: Set<URL>, in tab: (any WKWebExtensionTab)?,
                                       for extensionContext: WKWebExtensionContext,
                                       completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        let patterns = Set(urls.compactMap { url -> String? in
            guard let scheme = url.scheme, let host = url.host(percentEncoded: false) else { return nil }
            return "\(scheme)://\(host)/*"
        })
        let request = runtimeRequest(extensionContext, permissions: [], matchPatterns: Array(patterns))
        Task {
            completionHandler(await ask(request) ? urls : [], nil)
        }
    }

    private func runtimeRequest(_ context: WKWebExtensionContext, permissions: [String], matchPatterns: [String],
                                allHosts: Bool = false) -> ExtensionPermissionRequest {
        ExtensionPermissionRequest(extensionID: context.uniqueIdentifier,
                                   displayName: context.webExtension.displayName ?? context.uniqueIdentifier,
                                   moment: .runtime, permissions: permissions, matchPatterns: matchPatterns,
                                   hasAccessToAllHosts: allHosts,
                                   icon: context.webExtension.icon(for: CGSize(width: 64, height: 64)))
    }

    private func ask(_ request: ExtensionPermissionRequest) async -> Bool {
        guard let permissionRequests else { return false }
        return await permissionRequests(request)
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

/// An extension is read from a folder or a ZIP on disk only.
struct ExtensionFolderUnreadable: LocalizedError {
    let folder: URL
    var errorDescription: String? { "\(folder.absoluteString) is not a folder on this Mac" }
}

/// Where a Profile keeps its website data and its extensions' state. Tests use `.inMemory`, which writes nothing.
public enum WebsiteStorage: Sendable {
    case onDisk
    case inMemory
}
