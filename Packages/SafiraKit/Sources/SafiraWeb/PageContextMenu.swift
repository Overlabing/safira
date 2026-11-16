// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import os
import WebKit

/// What a right-clicked point of a page holds, read from the page's DOM in Safira's content world.
struct PageHit: Equatable, Sendable {
    var link: URL?
    var image: URL?
    var media: URL?
    var frame: URL?

    static let script = """
        const element = document.elementFromPoint(x, y);
        if (!element) { return {}; }
        const href = (node, attribute) => node ? (node.currentSrc || node[attribute] || null) : null;
        const link = element.closest('a[href], area[href]');
        return {
            link: link && typeof link.href === 'string' ? link.href : null,
            image: href(element.closest('img'), 'src'),
            media: href(element.closest('video, audio'), 'src'),
            frame: href(element.closest('iframe, frame'), 'src'),
        };
        """

    init(link: URL? = nil, image: URL? = nil, media: URL? = nil, frame: URL? = nil) {
        self.link = link
        self.image = image
        self.media = media
        self.frame = frame
    }

    init(_ result: Any?) {
        let values = result as? [String: Any] ?? [:]
        func url(_ key: String) -> URL? {
            (values[key] as? String).flatMap(URL.init(string:)).flatMap { ["http", "https", "data", "blob", "file"]
                .contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        }
        self.init(link: url("link"), image: url("image"), media: url("media"), frame: url("frame"))
    }
}

/// WebKit's context menu items that do nothing unless the app handles them, and what Safira does with each: a download
/// in the Tab's Profile, or a new Tab next to the current one.
enum PageMenuAction: String, CaseIterable, Sendable {
    case downloadImage = "WKMenuItemIdentifierDownloadImage"
    case downloadLinkedFile = "WKMenuItemIdentifierDownloadLinkedFile"
    case downloadMedia = "WKMenuItemIdentifierDownloadMedia"
    case openLinkInNewTab = "WKMenuItemIdentifierOpenLinkInNewWindow"
    case openImageInNewTab = "WKMenuItemIdentifierOpenImageInNewWindow"
    case openMediaInNewTab = "WKMenuItemIdentifierOpenMediaInNewWindow"
    case openFrameInNewTab = "WKMenuItemIdentifierOpenFrameInNewWindow"

    /// The action for a menu item WebKit built, by its identifier; nil for the items WebKit handles itself.
    init?(item: NSMenuItem) {
        guard let identifier = item.identifier?.rawValue else { return nil }
        self.init(rawValue: identifier)
    }

    /// Every item identifier WebKit is known to use. A menu with none of them means WebKit changed its identifiers.
    static let knownIdentifiers: Set<String> = Set([
        "AddHighlightToCurrentQuickNote", "AddHighlightToNewQuickNote", "CheckGrammarWithSpelling", "CheckSpelling",
        "CheckSpellingWhileTyping", "Copy", "CopyImage", "CopyLink", "CopyLinkWithHighlight", "CopyMediaLink",
        "CopySubject", "DownloadImage", "DownloadLinkedFile", "DownloadMedia", "GoBack", "GoForward", "InspectElement",
        "LookUp", "OpenFrameInNewWindow", "OpenImageInNewWindow", "OpenLink", "OpenLinkInNewWindow",
        "OpenMediaInNewWindow", "Paste", "PauseAllAnimations", "PauseAnimation", "PlayAllAnimations", "PlayAnimation",
        "Proofread", "Reload", "RevealImage", "Rewrite", "SearchWeb", "ShareMenu", "ShowHideMediaControls",
        "ShowHideMediaStats", "ShowSpellingPanel", "ShowSubstitutions", "SmartCopyPaste", "SmartDashes", "SmartLinks",
        "SmartQuotes", "SpeechMenu", "SpellingMenu", "SubstitutionsMenu", "Summarize", "TextReplacement",
        "ToggleFullScreen", "TogglePictureInPicture", "ToggleVideoViewer", "Translate", "WritingTools",
    ].map { "WKMenuItemIdentifier" + $0 })

    /// Whether a menu (its submenus included) holds no item WebKit is known to build: then the identifiers Safira
    /// matches have likely changed, and its items would be left inert.
    static func hasNoKnownItem(_ menu: NSMenu) -> Bool {
        !menu.items.contains { item in
            knownIdentifiers.contains(item.identifier?.rawValue ?? "") || item.submenu.map { !hasNoKnownItem($0) } == true
        }
    }

    var isDownload: Bool {
        switch self {
        case .downloadImage, .downloadLinkedFile, .downloadMedia: true
        case .openLinkInNewTab, .openImageInNewTab, .openMediaInNewTab, .openFrameInNewTab: false
        }
    }

    /// The address the action works on, in what the click hit. A download starts only from an http or https address:
    /// a data, blob or file address gives none, so its item is removed.
    func url(in hit: PageHit) -> URL? {
        guard let url = address(in: hit) else { return nil }
        guard isDownload else { return url }
        return ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? url : nil
    }

    private func address(in hit: PageHit) -> URL? {
        switch self {
        case .downloadImage, .openImageInNewTab: hit.image
        case .downloadLinkedFile, .openLinkInNewTab: hit.link
        case .downloadMedia, .openMediaInNewTab: hit.media
        case .openFrameInNewTab: hit.frame
        }
    }

    /// Safira opens Tabs, not windows: the "New Window" items say so.
    var title: String? {
        switch self {
        case .openLinkInNewTab:
            String(localized: "Open Link in New Tab", table: "SafiraWeb", bundle: .module, comment: "Page context menu")
        case .openImageInNewTab:
            String(localized: "Open Image in New Tab", table: "SafiraWeb", bundle: .module, comment: "Page context menu")
        case .openMediaInNewTab:
            String(localized: "Open Video in New Tab", table: "SafiraWeb", bundle: .module, comment: "Page context menu")
        case .openFrameInNewTab:
            String(localized: "Open Frame in New Tab", table: "SafiraWeb", bundle: .module, comment: "Page context menu")
        case .downloadImage, .downloadLinkedFile, .downloadMedia: nil
        }
    }
}

/// Safira's web view: it gives WebKit's context menu items that need the app something to do (#131). The page under
/// the pointer is read when the secondary click goes down, before WebKit opens its menu. When that reading is back as
/// the menu opens, an item whose address is not found there (an image inside another site's frame, a `data:` image to
/// download) is removed. When it is not back yet, the item stays, and choosing it reads the point again: an item that
/// still finds no address does nothing and says so in the log, never a silent failure.
@MainActor
final class SafiraWebView: WKWebView {
    var onMenuAction: (@MainActor (PageMenuAction, URL) -> Void)?
    /// What runs a JavaScript reading of the page; tests replace it to hold a reading back.
    var readPage: (@MainActor (SafiraWebView, String, [String: Any]) async -> Any?) = { view, script, arguments in
        try? await view.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: WebKitPage.contentWorld)
    }
    private var hitTest: Task<PageHit, Never>?
    private var hitPoint: NSPoint?
    private var finishedHit: PageHit?
    static let log = Logger(subsystem: "com.overlabing.safira", category: "PageContextMenu")

    /// A retargeted item's choice: the action, the point it applies to and the reading of it, which outlive the menu.
    final class Choice: NSObject {
        let action: PageMenuAction
        let point: NSPoint
        let hit: Task<PageHit, Never>

        init(action: PageMenuAction, point: NSPoint, hit: Task<PageHit, Never>) {
            self.action = action
            self.point = point
            self.hit = hit
        }
    }

    /// Whether the last point asked for has been read.
    var hasFinishedHitTest: Bool { finishedHit != nil }

    override func rightMouseDown(with event: NSEvent) {
        startHitTest(at: event)
        super.rightMouseDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { startHitTest(at: event) }
        super.mouseDown(with: event)
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        if hitTest == nil { startHitTest(at: event) }
        if PageMenuAction.hasNoKnownItem(menu) {
            Self.log.debug("A page context menu opened with no item identifier Safira knows: WebKit may have renamed them")
        }
        retarget(menu)
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        hitTest = nil
        hitPoint = nil
        finishedHit = nil
    }

    /// Points WebKit's items at Safira's actions, renames the "New Window" ones, and removes those that cannot work.
    func retarget(_ menu: NSMenu) {
        guard let hitTest, let hitPoint else { return }
        for item in menu.items {
            if let submenu = item.submenu { retarget(submenu) }
            guard let action = PageMenuAction(item: item) else { continue }
            if let finishedHit, action.url(in: finishedHit) == nil {
                menu.removeItem(item)
                continue
            }
            item.target = self
            item.action = #selector(performPageMenuAction(_:))
            item.representedObject = Choice(action: action, point: hitPoint, hit: hitTest)
            if let title = action.title { item.title = title }
        }
    }

    /// Reads what is under the event's point in the page.
    func startHitTest(at event: NSEvent) {
        startHitTest(at: convert(event.locationInWindow, from: nil))
    }

    func startHitTest(at point: NSPoint) {
        finishedHit = nil
        hitPoint = point
        let task = Task { @MainActor [weak self] () -> PageHit in
            guard let self else { return PageHit() }
            let hit = await read(at: point)
            if hitPoint == point { finishedHit = hit }
            return hit
        }
        hitTest = task
    }

    /// What the page holds at a point of this view, in CSS pixels once the page's zoom and magnification are taken out.
    func read(at point: NSPoint) async -> PageHit {
        let scale = max(magnification * pageZoom, 0.01)
        let y = isFlipped ? point.y : bounds.height - point.y
        return PageHit(await readPage(self, PageHit.script, ["x": Double(point.x / scale), "y": Double(y / scale)]))
    }

    @objc func performPageMenuAction(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? Choice else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            var url = choice.action.url(in: await choice.hit.value)
            if url == nil { url = choice.action.url(in: await read(at: choice.point)) }
            guard let url else {
                Self.log.info("\(choice.action.rawValue, privacy: .public) found no address it can use; nothing done")
                return
            }
            onMenuAction?(choice.action, url)
        }
    }
}
