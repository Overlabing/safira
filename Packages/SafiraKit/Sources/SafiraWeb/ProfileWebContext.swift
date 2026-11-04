// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import SafiraCore
import SafiraSession
import WebKit

/// The only owner of a Profile's website data store, and the only place that builds web view configurations.
/// This file is the one place allowed to name website data stores (scripts/guard-singletons.sh).
@MainActor
public final class ProfileWebContext {
    /// The Profile this context belongs to; for a Private window, the Profile it is attached to.
    public let profileID: ProfileID
    public let dataStore: WKWebsiteDataStore
    /// True for a Private window's context: its data store lives in memory only.
    public let isPrivate: Bool
    /// Receives the navigation events of the pages made after it is set.
    public var diagnostics: DiagnosticLogger?
    /// Read each time a page is built: a change reaches the pages created after it, never the ones already open.
    public var webContentSettings: WebContentSettings
    /// What this Profile remembers about the sites that asked for the camera, the microphone or the location.
    public let permissions: SitePermissions
    /// This Profile's downloads, whichever Tab started them. Another Profile has its own list.
    public let downloads: ProfileDownloads
    /// Asks the user about a request the Profile has no decision for. Without it, such a request is denied.
    public var permissionPrompt: (@MainActor (PermissionPrompt) async -> PermissionAnswer)?
    /// The live pages of this Profile's Tabs. They live here, outside the views, until their Tab closes.
    private var pages: [TabID: WebKitPage] = [:]
    /// The live pages of this Profile's popups, which share their opener's configuration.
    private var popupPages: [PopupID: WebKitPage] = [:]
    private let pageEvents = PageEventHandler()
    private var downloadController: DownloadController!

    /// - Parameter downloads: where this Profile's downloads are listed; the default keeps them for this run only.
    public init(profileID: ProfileID, webContentSettings: WebContentSettings = WebContentSettings(),
                permissions: SitePermissions = SitePermissions(), downloads: ProfileDownloads = ProfileDownloads()) {
        self.profileID = profileID
        self.webContentSettings = webContentSettings
        self.permissions = permissions
        self.downloads = downloads
        self.dataStore = WKWebsiteDataStore(forIdentifier: profileID.rawValue)
        isPrivate = false
        pageEvents.context = self
        installDownloadController()
    }

    private func installDownloadController() {
        downloadController = DownloadController(downloads: downloads) { [unowned self] in
            // Only the data store matters to a download: no script, no page.
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = dataStore
            return WKWebView(frame: .zero, configuration: configuration)
        }
        downloads.engine = downloadController
    }

    /// Where this Profile's downloads are saved: the user's Downloads folder unless changed.
    public var downloadsDirectory: URL {
        get { downloadController.directory }
        set { downloadController.directory = newValue }
    }

    /// Where files go when the user declines access to the Downloads folder: a folder of the app's own container.
    public var downloadsFallbackDirectory: URL {
        get { downloadController.fallbackDirectory }
        set { downloadController.fallbackDirectory = newValue }
    }

    /// Decides whether a folder may be used, in place of macOS's own consent prompt. Tests replace it.
    public var downloadsAccess: @MainActor (URL) async -> Bool {
        get { downloadController.access }
        set { downloadController.access = newValue }
    }

    /// Asks for access to the Downloads folder now, at a moment the user chose, so that the first download does not
    /// have to. Returns once the user has answered; the main thread is never held meanwhile.
    public func prepareDownloadsAccess() async {
        await downloadController.resolveDirectory()
    }

    /// Stops the Profile's running downloads, for a Profile that goes away.
    public func cancelDownloads() async {
        await downloadController.cancelAll()
    }

    /// The context of a Private window attached to a Profile. Its data store is a new non-persistent one, which WebKit
    /// keeps in memory and writes nowhere ("no data will be written to the file system"), and its site permissions are
    /// remembered in memory only. It reads nothing of the Profile's data store, and the Profile's cannot read it.
    public init(privateWindowOf profileID: ProfileID, webContentSettings: WebContentSettings = WebContentSettings()) {
        self.profileID = profileID
        self.webContentSettings = webContentSettings
        permissions = SitePermissions()
        // No database: what a Private window downloads is listed for this run only, never in the Profile's database.
        downloads = ProfileDownloads()
        dataStore = WKWebsiteDataStore.nonPersistent()
        isPrivate = true
        pageEvents.context = self
        installDownloadController()
    }

    /// Empties the data store of a Private window now, without waiting for WebKit to release it.
    public func eraseWebsiteData() async {
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    public func makeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        // Explicit, so hidden Tabs do not depend on the default linked to the SDK version (architecture §4.1).
        configuration.preferences.inactiveSchedulingPolicy = .suspend
        pageEvents.install(in: configuration.userContentController)
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

    public func webView(forPopup id: PopupID) -> WKWebView? {
        popupPages[id]?.webView
    }

    /// Whether a site may use these capabilities now: the Profile's remembered decision, or else the user's answer,
    /// which is remembered when the user asked for it. Another Profile's decisions are never consulted.
    public func permissionDecision(requesting kinds: [PermissionKind], at origin: SiteOrigin) async -> PermissionDecision {
        switch permissions.verdict(requesting: kinds, at: origin) {
        case .allow: return .allow
        case .deny: return .deny
        case .ask(let missing):
            guard let permissionPrompt else { return .deny }
            let answer = await permissionPrompt(PermissionPrompt(profileID: profileID, origin: origin, kinds: missing))
            if answer.remember {
                permissions.remember(answer.decision, for: missing, at: origin)
            }
            return answer.decision
        }
    }

    /// Removes the website data this Profile's store modified at or after `start`: cookies, local and session storage,
    /// IndexedDB, service workers, caches and the rest. Open pages keep running: what they already hold in memory stays
    /// until they reload, but their stored data is gone.
    public func clearWebsiteData(since start: Date) async {
        // WebKit raises an exception, and the app dies, when the start is later than now (it builds a Screen Time
        // interval from it), so a start in the future is read as now.
        await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: min(start, Date()))
    }

    public static func removeDataStore(of profileID: ProfileID) async throws {
        try await WKWebsiteDataStore.remove(forIdentifier: profileID.rawValue)
    }

    /// Whether WebKit keeps a data store for this Profile on disk.
    public static func dataStoreExists(for profileID: ProfileID) async -> Bool {
        await WKWebsiteDataStore.allDataStoreIdentifiers.contains(profileID.rawValue)
    }

    /// `configuration` is either this Profile's or the copy WebKit hands over for a `target=_blank` link or a popup,
    /// which WebKit derives from the opener's, so all use this Profile's data store.
    private func register(_ tabID: TabID, configuration: WKWebViewConfiguration) -> WebKitPage {
        let page = makePage(configuration: configuration) { [weak self] in self?.unregister(tabID) }
        pages[tabID] = page
        return page
    }

    private func registerPopup(_ id: PopupID, configuration: WKWebViewConfiguration) -> WebKitPage {
        let page = makePage(configuration: configuration) { [weak self] in self?.unregisterPopup(id) }
        popupPages[id] = page
        return page
    }

    private func makePage(configuration: WKWebViewConfiguration, onClose: @escaping @MainActor () -> Void) -> WebKitPage {
        WebKitPage(
            configuration: configuration,
            diagnostics: diagnostics,
            makeNewTabPage: { [weak self] configuration in
                guard let self else { return nil }
                let id = TabID()
                return (id, register(id, configuration: configuration))
            },
            makePopupPage: { [weak self] configuration in
                guard let self else { return nil }
                let id = PopupID()
                return (id, registerPopup(id, configuration: configuration))
            },
            decidePermission: { [weak self] origin, kinds in
                await self?.permissionDecision(requesting: kinds, at: origin) ?? .deny
            },
            startDownload: { [weak self] in self?.downloadController.adopt($0) },
            onClose: onClose
        )
    }

    private func unregister(_ tabID: TabID) {
        guard let page = pages.removeValue(forKey: tabID) else { return }
        releaseHandlers(of: page)
    }

    private func unregisterPopup(_ id: PopupID) {
        guard let page = popupPages.removeValue(forKey: id) else { return }
        releaseHandlers(of: page)
    }

    /// A `target=_blank` page or a popup shares its opener's content controller; its handlers go with the last page
    /// using it.
    private func releaseHandlers(of page: WebKitPage) {
        let controller = page.webView.configuration.userContentController
        let shared = (Array(pages.values) + Array(popupPages.values))
            .contains { $0.webView.configuration.userContentController === controller }
        if !shared {
            controller.removeAllScriptMessageHandlers()
        }
    }

    fileprivate func page(showing webView: WKWebView?) -> WebKitPage? {
        (Array(pages.values) + Array(popupPages.values)).first { $0.webView === webView }
    }
}

/// The page events Safira listens to, sent by scripts that run in Safira's own content world, out of the page's reach,
/// and that send no page data:
/// - a media element starts or stops, so the page asks WebKit for its playback state;
/// - a frame has a password field, so the Tab's navigation state stays off the disk (decision D1). Fields added later,
///   for example by a sign-in dialog, count too; fields inside a shadow root are not seen.
@MainActor
private final class PageEventHandler: NSObject, WKScriptMessageHandler {
    weak var context: ProfileWebContext?
    private static let world = WKContentWorld.world(name: "Safira")
    private static let media = "media"
    private static let passwordField = "passwordField"
    private static let scripts = [
        WKUserScript(
            source: """
            for (const type of ["play", "playing", "pause", "ended", "emptied"]) {
                document.addEventListener(type, () => window.webkit.messageHandlers.media.postMessage(null), true);
            }
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: world
        ),
        WKUserScript(
            source: """
            (() => {
                const found = () => document.querySelector('input[type="password" i]') !== null;
                const report = () => window.webkit.messageHandlers.passwordField.postMessage(null);
                if (found()) { report(); return; }
                const observer = new MutationObserver(() => {
                    if (found()) { observer.disconnect(); report(); }
                });
                observer.observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: ["type"] });
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: world
        ),
    ]

    func install(in controller: WKUserContentController) {
        Self.scripts.forEach(controller.addUserScript)
        controller.add(self, contentWorld: Self.world, name: Self.media)
        controller.add(self, contentWorld: Self.world, name: Self.passwordField)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let page = context?.page(showing: message.webView) else { return }
        switch message.name {
        case Self.media: page.refreshMediaState()
        case Self.passwordField: page.passwordFieldFound()
        default: break
        }
    }
}
