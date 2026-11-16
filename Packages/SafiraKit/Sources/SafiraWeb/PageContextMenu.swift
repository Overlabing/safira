// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
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

    var isDownload: Bool {
        switch self {
        case .downloadImage, .downloadLinkedFile, .downloadMedia: true
        case .openLinkInNewTab, .openImageInNewTab, .openMediaInNewTab, .openFrameInNewTab: false
        }
    }

    /// The address the action works on, in what the click hit.
    func url(in hit: PageHit) -> URL? {
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
/// the pointer is read when the secondary click goes down, before WebKit opens its menu; an item whose address is not
/// found there (an image inside another site's frame) is removed rather than left inert.
@MainActor
final class SafiraWebView: WKWebView {
    var onMenuAction: (@MainActor (PageMenuAction, URL) -> Void)?
    private var hitTest: Task<PageHit, Never>?
    private var finishedHit: PageHit?

    /// A retargeted item's choice: the action and the reading of the point it applies to, which outlives the menu.
    private final class Choice: NSObject {
        let action: PageMenuAction
        let hit: Task<PageHit, Never>

        init(action: PageMenuAction, hit: Task<PageHit, Never>) {
            self.action = action
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
        retarget(menu)
    }

    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        super.didCloseMenu(menu, with: event)
        hitTest = nil
        finishedHit = nil
    }

    /// Points WebKit's items at Safira's actions, renames the "New Window" ones, and removes those that cannot work.
    func retarget(_ menu: NSMenu) {
        guard let hitTest else { return }
        for item in menu.items {
            if let submenu = item.submenu { retarget(submenu) }
            guard let action = PageMenuAction(item: item) else { continue }
            if let finishedHit, action.url(in: finishedHit) == nil {
                menu.removeItem(item)
                continue
            }
            item.target = self
            item.action = #selector(performPageMenuAction(_:))
            item.representedObject = Choice(action: action, hit: hitTest)
            if let title = action.title { item.title = title }
        }
    }

    /// Reads what is under the event's point in the page.
    func startHitTest(at event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startHitTest(at: point)
    }

    func startHitTest(at point: NSPoint) {
        finishedHit = nil
        let scale = max(magnification * pageZoom, 0.01)
        let y = isFlipped ? point.y : bounds.height - point.y
        let task = Task { @MainActor [weak self] () -> PageHit in
            guard let self else { return PageHit() }
            let result = try? await callAsyncJavaScript(
                PageHit.script, arguments: ["x": Double(point.x / scale), "y": Double(y / scale)], in: nil,
                contentWorld: WebKitPage.contentWorld)
            let hit = PageHit(result)
            finishedHit = hit
            return hit
        }
        hitTest = task
    }

    @objc private func performPageMenuAction(_ sender: NSMenuItem) {
        guard let choice = sender.representedObject as? Choice else { return }
        Task { @MainActor [weak self] in
            guard let url = choice.action.url(in: await choice.hit.value) else { return }
            self?.onMenuAction?(choice.action, url)
        }
    }
}
