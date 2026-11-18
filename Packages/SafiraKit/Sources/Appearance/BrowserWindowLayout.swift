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
    /// The Library's view, over the column and beside the pushed card while it is open; hidden, and kept, after.
    private var library: NSView?
    private var libraryLeading = NSLayoutConstraint()
    private var libraryWidth = NSLayoutConstraint()
    /// Whether the Library is open, or opening.
    public private(set) var isLibraryShown = false

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

    /// None: the sidebar button is in the column's head, beside the window's buttons (ThemeKit's sidebar head).
    public var toolbarItems: [NSToolbarItem.Identifier] {
        NSSplitViewItem.sidebarHeadToolbarItems
    }

    override public func viewDidLayout() {
        super.viewDidLayout()
        updateCardTop(animated: false)
        if isLibraryShown {
            let push = libraryPush
            if libraryWidth.constant != push.libraryWidth { libraryWidth.constant = push.libraryWidth }
            if canvas.push != push.detailOffset(1) { canvas.setPush(push.detailOffset(1), animated: false) }
        }
    }

    // MARK: Library

    /// Where the Library's views stand for the window's width now (ThemeKit's `LibraryPush`).
    private var libraryPush: LibraryPush {
        LibraryPush(windowWidth: view.bounds.width, sidebarWidth: columnItem.isCollapsed ? 0 : column.view.frame.width,
                    tokens: tokens)
    }

    /// Opens the Library, as Zen does: `library` slides in from the leading edge over the column, which fades out, and
    /// the page's card is pushed toward the trailing edge at its own size, `Size.libraryPeek` of it left in sight. With
    /// Reduce Motion nothing moves: the Library and the column cross-fade.
    public func showLibrary(_ library: NSView, animated: Bool) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let push = libraryPush
        let wasShown = isLibraryShown
        if self.library !== library { install(library) }
        isLibraryShown = true
        library.isHidden = false
        libraryWidth.constant = push.libraryWidth
        if !wasShown {
            libraryLeading.constant = animated && !reduceMotion ? push.libraryOffset(0) : 0
            library.alphaValue = animated && reduceMotion ? 0 : 1
            view.layoutSubtreeIfNeeded()
        }
        run(animated) { [self] in
            (animated && !reduceMotion ? libraryLeading.animator() : libraryLeading).constant = 0
            (animated ? library.animator() : library).alphaValue = 1
            canvas.setPush(push.detailOffset(1), animated: animated && !reduceMotion)
            (animated ? column.view.animator() : column.view).alphaValue = 0
        } completion: { [weak self] in
            if self?.isLibraryShown == true { self?.column.view.isHidden = true }
        }
    }

    /// Closes the Library: the reverse of `showLibrary`, back to the column and the card where they were.
    public func hideLibrary(animated: Bool) {
        guard isLibraryShown, let library else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let push = libraryPush
        isLibraryShown = false
        column.view.isHidden = false
        run(animated) { [self] in
            if animated && !reduceMotion {
                libraryLeading.animator().constant = push.libraryOffset(0)
            } else {
                (animated ? library.animator() : library).alphaValue = 0
            }
            canvas.setPush(0, animated: animated && !reduceMotion)
            (animated ? column.view.animator() : column.view).alphaValue = 1
        } completion: { [weak self] in
            guard let self, !isLibraryShown else { return }
            library.isHidden = true
        }
    }

    private func install(_ library: NSView) {
        self.library?.removeFromSuperview()
        self.library = library
        library.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(library, positioned: .below, relativeTo: edge)
        libraryLeading = library.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        libraryWidth = library.widthAnchor.constraint(equalToConstant: libraryPush.libraryWidth)
        NSLayoutConstraint.activate([
            library.topAnchor.constraint(equalTo: view.topAnchor),
            library.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            libraryLeading,
            libraryWidth,
        ])
    }

    /// Runs `changes` in the Library's motion (the curve and settling time of Zen's spring), or at once.
    private func run(_ animated: Bool, _ changes: @escaping () -> Void, completion: @escaping @MainActor () -> Void) {
        guard animated else {
            changes()
            completion()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            let points = LibraryPush.timingControlPoints
            context.duration = LibraryPush.duration
            context.timingFunction = CAMediaTimingFunction(controlPoints: points.0, points.1, points.2, points.3)
            context.allowsImplicitAnimation = true
            changes()
        } completionHandler: {
            MainActor.assumeIsolated { completion() }
        }
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

/// The sidebar button of the column's head calls `toggleSidebar(_:)` on the split view controller, which would collapse
/// the column behind the window's back: the window decides instead, so that the button and Compact mode stay one state.
/// The kit's seamless split keeps the divider's resize zone over the card's margin although it draws nothing.
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
/// While the Library is open the card is pushed toward the trailing edge at its own size (`setPush`), a strip of it in
/// sight under a cover that says a click goes back; the page is never removed, so it comes back as it was.
@MainActor
public final class PageCanvasView: NSView {
    private let tokens = DesignTokens.standard
    private let clip = NSView()
    /// The page and what floats over it: hidden as one while a pane is shown, each keeping its own hidden state.
    private let content = NSView()
    private let peek = PeekCover()
    private var top = NSLayoutConstraint()
    private var leading = NSLayoutConstraint()
    private var trailing = NSLayoutConstraint()

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
        leading = clip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset)
        trailing = clip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset)
        NSLayoutConstraint.activate([
            leading,
            trailing,
            top,
            clip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
        Self.fill(clip, with: content)
        for view in [page, commandBar] {
            Self.fill(content, with: view)
        }
        banner.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(banner, positioned: .below, relativeTo: commandBar)
        let float = tokens.spacing.pillFloat
        NSLayoutConstraint.activate([
            banner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: float),
            banner.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -float),
            banner.topAnchor.constraint(equalTo: content.topAnchor, constant: float),
        ])
        if let findBar {
            findBar.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(findBar, positioned: .below, relativeTo: commandBar)
            NSLayoutConstraint.activate([
                findBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -float),
                findBar.topAnchor.constraint(equalTo: content.topAnchor, constant: float),
                findBar.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: float),
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

    /// The card's distance from its place, toward the trailing edge.
    public var push: CGFloat { leading.constant - tokens.spacing.canvasInset }

    /// Moves the card `offset` toward the trailing edge, keeping its size; 0 puts it back. The window clips what goes
    /// past its edge.
    public func setPush(_ offset: CGFloat, animated: Bool) {
        let inset = tokens.spacing.canvasInset
        (animated ? leading.animator() : leading).constant = inset + offset
        (animated ? trailing.animator() : trailing).constant = -inset + offset
    }

    /// While the Library is open: a cover over the card that dims it, says a click on it goes back, and calls
    /// `onClick`; `label` is what VoiceOver says of it. Nil takes the cover away.
    public func showPeek(label: String?, hint: String = "", onClick: (() -> Void)? = nil) {
        peek.onClick = onClick
        if let label {
            peek.setAccessibilityLabel(label)
            peek.hint.stringValue = hint
            if peek.superview == nil { Self.fill(clip, with: peek) }
        } else {
            peek.removeFromSuperview()
        }
    }

    /// Whether the peek cover is over the card.
    public var showsPeek: Bool { peek.superview != nil }

    /// Clicks the peek cover, as a test or VoiceOver's press would.
    public func pressPeek() {
        _ = peek.accessibilityPerformPress()
    }

    private static func fill(_ container: NSView, with view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

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

/// The toolbar of a window with the kit's sidebar head: no items, in the compact style, so that its band is the head's
/// title bar row and the window's buttons sit on that row's line, as in Zen.
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
        window.toolbarStyle = .unifiedCompact
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

/// The cover over the pushed page while the Library is open: the page dimmed, a hint in the strip left in sight, and a
/// click anywhere on it goes back. For VoiceOver it is one button.
@MainActor
private final class PeekCover: NSView {
    var onClick: (() -> Void)?
    let hint = NSTextField(wrappingLabelWithString: "")
    private let tokens = DesignTokens.standard

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        hint.textColor = .white.withAlphaComponent(0.85)
        hint.alignment = .center
        hint.maximumNumberOfLines = 4
        hint.setAccessibilityElement(false)
        hint.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hint)
        // The strip in sight is `Size.libraryPeek` less the card's inset: the hint sits in it.
        let strip = tokens.size.libraryPeek - tokens.spacing.canvasInset
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DesignTokens.Spacing.s),
            hint.widthAnchor.constraint(equalToConstant: strip - 2 * DesignTokens.Spacing.s),
            hint.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return onClick != nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
