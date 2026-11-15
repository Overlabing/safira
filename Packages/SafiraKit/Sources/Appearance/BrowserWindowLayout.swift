// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import DesignKit
import SafiraCore
import SwiftUI

/// The window shared by the Main window and Private windows: ThemeKit's sidebar in an AppKit window, as the kit's docs
/// set it up ("Sidebar", "In an AppKit window"). The Theme's gradient (`WindowBackground`) lies under the whole split;
/// the column sits on it with no surface of its own (`SidebarSurface.windowBackground`: no material, no tone, a divider
/// that draws nothing), as in Zen, so the page's card, beside it in the kit's detail card, is the only boundary. In
/// Compact mode the column collapses, and comes back from the left edge on demand, still on the gradient. The pointer
/// is watched with AppKit tracking areas: SwiftUI's `onHover` is unreliable over a web view (docs/architecture-v1.md
/// §1.3).
@MainActor
public final class BrowserWindowLayout: NSViewController {
    /// The strip at the window's left edge that brings the sidebar back in Compact mode.
    public static let compactEdgeWidth: CGFloat = 6

    /// The pointer left the revealed sidebar.
    public var onPointerLeftSidebar: (() -> Void)?
    /// The pointer touched the window's left edge while the sidebar is collapsed in Compact mode.
    public var onPointerReachedEdge: (() -> Void)?
    /// The system's sidebar button, or a divider dragged shut: the window decides what showing or hiding means.
    public var onToggleSidebar: (() -> Void)?

    private let tokens = DesignTokens.standard
    private let background: NSView
    private let column: NSViewController
    private let canvas: PageCanvasView
    private let split = SidebarSplitController()
    private let columnItem: NSSplitViewItem
    private let pageItem: NSSplitViewItem
    private let edge = EdgeView()
    private let pointer = PointerWatch()
    private var collapseObservation: NSKeyValueObservation?
    private var fullScreen = FullScreenToolbar()
    private var fullScreenObservers: [any NSObjectProtocol] = []
    /// What the layout wants the column to be; a change the split makes on its own is reported to the window.
    private var wantsCollapsed = false

    /// `background` draws the Theme's gradient under the whole window; `column` is the sidebar's SwiftUI column, a `List`
    /// with `sidebarColumn(field:header:bottomBar:)`.
    public init(background: NSView, column: some View, canvas: PageCanvasView) {
        self.background = background
        self.canvas = canvas
        columnItem = NSSplitViewItem.sidebar(hosting: column, tokens: tokens, surface: .windowBackground)
        self.column = columnItem.viewController
        let page = NSViewController()
        page.view = canvas
        pageItem = NSSplitViewItem(viewController: page)
        super.init(nibName: nil, bundle: nil)
        split.onToggleSidebar = { [weak self] in self?.onToggleSidebar?() }
        configureColumn()
        split.addSplitViewItem(columnItem)
        split.addSplitViewItem(pageItem)
        pointer.onExit = { [weak self] in self?.onPointerLeftSidebar?() }
        self.column.view.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: pointer))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override public func loadView() {
        view = NSView()
        for subview in [background, split.view] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                subview.topAnchor.constraint(equalTo: view.topAnchor),
                subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        addChild(split)
        edge.translatesAutoresizingMaskIntoConstraints = false
        edge.onPointerEntered = { [weak self] in self?.onPointerReachedEdge?() }
        edge.isHidden = true
        view.addSubview(edge)
        NSLayoutConstraint.activate([
            edge.topAnchor.constraint(equalTo: view.topAnchor),
            edge.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: Self.compactEdgeWidth),
            edge.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ])
    }

    /// True when the keyboard focus is inside the sidebar.
    public var sidebarHasFocus: Bool {
        (view.window?.firstResponder as? NSView)?.isDescendant(of: column.view) == true
    }

    /// The system's sidebar button at the column's edge and the separator that follows its width.
    public var toolbarItems: [NSToolbarItem.Identifier] {
        NSSplitViewItem.sidebarToolbarItems
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        updateCardTop(animated: false)
    }

    override public func viewWillAppear() {
        super.viewWillAppear()
        guard fullScreenObservers.isEmpty, let window = view.window else { return }
        let center = NotificationCenter.default
        let enter = center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.windowWillEnterFullScreen() }
        }
        let exit = center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.windowWillExitFullScreen() }
        }
        fullScreenObservers = [enter, exit]
    }

    override public func viewDidDisappear() {
        super.viewDidDisappear()
        fullScreenObservers.forEach(NotificationCenter.default.removeObserver)
        fullScreenObservers = []
    }

    private func windowWillEnterFullScreen() {
        guard let toolbar = view.window?.toolbar else { return }
        toolbar.isVisible = fullScreen.willEnter(toolbarVisible: toolbar.isVisible)
        view.needsLayout = true
    }

    private func windowWillExitFullScreen() {
        guard let visible = fullScreen.willExit() else { return }
        view.window?.toolbar?.isVisible = visible
        view.needsLayout = true
    }

    public func apply(_ presentation: SidebarPresentation, animated: Bool) {
        let collapsed = !presentation.isSidebarShown
        edge.isHidden = !collapsed
        guard collapsed != wantsCollapsed || columnItem.isCollapsed != collapsed else { return }
        wantsCollapsed = collapsed
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if shouldAnimate {
            let motion = collapsed ? MotionRole.panelDisappear : MotionRole.panelAppear
            NSAnimationContext.runAnimationGroup { context in
                context.duration = motion.spec.duration.rawValue
                columnItem.animator().isCollapsed = collapsed
                updateCardTop(animated: true)
            }
        } else {
            columnItem.isCollapsed = collapsed
            updateCardTop(animated: false)
        }
    }

    /// The window's buttons and the sidebar button sit in the title bar at the top left. Beside the column they sit on
    /// the column, and the card starts `Spacing.canvasInset` from the window's top edge, as `SidebarDetail` does; with
    /// the column collapsed they would sit on the card, over the page, so the card starts under the title bar and they
    /// keep a strip of the gradient to themselves.
    private func updateCardTop(animated: Bool) {
        guard let window = view.window else { return }
        let titleBar = window.frame.height - window.contentLayoutRect.height
        canvas.setTopInset(wantsCollapsed ? titleBar : tokens.spacing.canvasInset, animated: animated)
    }

    /// The kit's widths for the column; only the window's own actions collapse it.
    private func configureColumn() {
        columnItem.minimumThickness = tokens.size.columnMin
        columnItem.maximumThickness = tokens.size.columnMax
        columnItem.canCollapse = true
        columnItem.canCollapseFromWindowResize = false
        columnItem.holdingPriority = .defaultLow + 10
        collapseObservation = columnItem.observe(\.isCollapsed) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.columnItem.isCollapsed != self.wantsCollapsed else { return }
                self.onToggleSidebar?()
            }
        }
    }
}

/// The system's sidebar button sends `toggleSidebar(_:)` to the split view controller, which would collapse the column
/// behind the window's back: the window decides instead, so that the button and Compact mode stay one state. The kit's
/// seamless split keeps the divider's resize zone over the card's margin although it draws nothing.
private final class SidebarSplitController: SeamlessSplitViewController {
    var onToggleSidebar: (() -> Void)?

    override func toggleSidebar(_ sender: Any?) {
        onToggleSidebar?()
    }
}

/// The page in the kit's detail card (`SidebarDetail`), in AppKit: the web view is an AppKit view the card must clip,
/// which a SwiftUI clip shape does not do for a hosted view. Inset `Spacing.canvasInset` from the detail's edges and from
/// the window's top edge, under the transparent toolbar (under the title bar when the column is collapsed); on the plain
/// background, rounded `Radius.canvas`, with a 1 pt `.separator` line on its edge. The page fills the card exactly.
/// The banner floats over the top of the card, the find bar at its top right, and the Command bar over the whole page.
@MainActor
public final class PageCanvasView: NSView {
    private let tokens = DesignTokens.standard
    private let clip = NSView()
    private var top = NSLayoutConstraint()

    public init(page: NSView, banner: NSView, findBar: NSView? = nil, commandBar: NSView) {
        super.init(frame: .zero)
        clip.wantsLayer = true
        clip.layer?.cornerRadius = tokens.radius.canvas
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.layer?.borderWidth = tokens.size.stroke
        clip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clip)
        let inset = tokens.spacing.canvasInset
        top = clip.topAnchor.constraint(equalTo: topAnchor, constant: inset)
        NSLayoutConstraint.activate([
            clip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            clip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            top,
            clip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
        for view in [page, commandBar] {
            view.translatesAutoresizingMaskIntoConstraints = false
            clip.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
                view.topAnchor.constraint(equalTo: clip.topAnchor),
                view.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            ])
        }
        banner.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(banner, positioned: .below, relativeTo: commandBar)
        let float = tokens.spacing.pillFloat
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: clip.leadingAnchor, constant: float),
            banner.trailingAnchor.constraint(equalTo: clip.trailingAnchor, constant: -float),
            banner.topAnchor.constraint(equalTo: clip.topAnchor, constant: float),
        ])
        if let findBar {
            findBar.translatesAutoresizingMaskIntoConstraints = false
            clip.addSubview(findBar, positioned: .below, relativeTo: commandBar)
            NSLayoutConstraint.activate([
                findBar.trailingAnchor.constraint(equalTo: clip.trailingAnchor, constant: -float),
                findBar.topAnchor.constraint(equalTo: clip.topAnchor, constant: float),
                findBar.leadingAnchor.constraint(greaterThanOrEqualTo: clip.leadingAnchor, constant: float),
            ])
        }
        updateOutline()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The card's frame in this view: what the page shows in.
    public var cardFrame: NSRect { clip.frame }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateOutline()
    }

    /// From the window's top edge to the card's top.
    public func setTopInset(_ inset: CGFloat, animated: Bool) {
        guard top.constant != inset else { return }
        (animated ? top.animator() : top).constant = inset
    }

    @objc private func accessibilityDisplayOptionsChanged(_ notification: Notification) {
        updateOutline()
    }

    /// The card's plain background, and its line: `.separator`, or `.secondary` under Increase Contrast, resolved in
    /// the view's appearance.
    private func updateOutline() {
        let color: NSColor = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ? .secondaryLabelColor : .separatorColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            clip.layer?.borderColor = color.cgColor
            clip.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }
}

/// The toolbar of a window with the kit's sidebar: the system's sidebar button and tracking separator, icons only, no
/// title.
@MainActor
public final class SidebarToolbar: NSObject, NSToolbarDelegate {
    private let items: [NSToolbarItem.Identifier]

    public init(items: [NSToolbarItem.Identifier]) {
        self.items = items
    }

    public func install(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: "Safira.sidebar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        items
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        items
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                        willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        nil
    }
}

/// Window full screen has no toolbar band (#123): AppKit draws the full screen toolbar in a system-grey band over the
/// Theme, and no public API paints that band (ThemeKit 0.2.12's changelog), so the toolbar hides while the window is in
/// full screen, as in Zen. The menu bar and the window's buttons still show at the top of the screen; the sidebar
/// stays reachable by its shortcut and, in Compact mode, from the left edge. Leaving full screen gives the toolbar back
/// as it was.
public enum SidebarFullScreen {
    public static func options(_ proposed: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        proposed.union([.autoHideToolbar, .autoHideMenuBar])
    }
}

/// Whether the window's toolbar shows, across full screen: hidden on the way in, back to what it was on the way out.
public struct FullScreenToolbar: Equatable, Sendable {
    /// What the toolbar was before full screen; nil outside full screen.
    private var visibleBefore: Bool?

    public init() {}

    public var isInFullScreen: Bool { visibleBefore != nil }

    /// The window starts entering full screen with its toolbar `visible`: the visibility to set now.
    public mutating func willEnter(toolbarVisible visible: Bool) -> Bool {
        if visibleBefore == nil { visibleBefore = visible }
        return false
    }

    /// The window starts leaving full screen: the visibility to set now, or nil to leave it.
    public mutating func willExit() -> Bool? {
        defer { visibleBefore = nil }
        return visibleBefore
    }
}

/// Reports the pointer leaving the column's view: the owner of its tracking area.
private final class PointerWatch: NSResponder {
    var onExit: (() -> Void)?

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }
}

/// A thin strip at the window's left edge that reports the pointer entering it.
private final class EdgeView: NSView {
    var onPointerEntered: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered?()
    }
}

/// Shows one page at a time, filling the card. Swapping only moves views in and out of the window: the pages stay
/// alive in the Profile's registry, so none reloads.
@MainActor
public final class TabHostView: NSView {
    private let emptyPage: NSView
    private var shown: NSView?

    /// `emptyPage` is shown while there is no page.
    public init(emptyPage: NSView) {
        self.emptyPage = emptyPage
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public func show(_ page: NSView?) {
        let next = page ?? emptyPage
        guard next !== shown else { return }
        let focusWasInPage = shown.map { previous in
            (window?.firstResponder as? NSView)?.isDescendant(of: previous) == true
        } ?? false
        shown?.removeFromSuperview()
        next.frame = bounds
        next.autoresizingMask = [.width, .height]
        addSubview(next)
        shown = next
        if focusWasInPage, page != nil {
            window?.makeFirstResponder(next)
        }
    }
}
