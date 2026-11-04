// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import DesignKit
import SafiraCore

/// The window shared by the Main window and Private windows, after Oisillon's: the Theme's gradient (`WindowBackground`)
/// under the whole window, title bar included; the sidebar column on one side and the page in its canvas on the other;
/// no bar above the page. The column sits in a plain split item, not a sidebar item, so macOS never dims its labels when
/// the window is inactive. In Compact mode the column leaves the split and comes back over the page from its own edge.
/// The pointer is watched with AppKit tracking areas: SwiftUI's `onHover` is unreliable over a web view
/// (docs/architecture-v1.md §1.3).
@MainActor
final class BrowserWindowLayout: NSViewController {
    /// The pointer left the revealed sidebar.
    var onPointerLeftSidebar: (() -> Void)?
    /// The pointer touched the window's edge on the sidebar's side in Compact mode.
    var onPointerReachedEdge: (() -> Void)?

    private let tokens = SafiraDesign.tokens
    private let background: NSView
    private let column: NSViewController
    private let canvas: PageCanvasView
    private let split = NSSplitViewController()
    private let columnItem: NSSplitViewItem
    private let pageItem: NSSplitViewItem
    private let overlay: OverlayView
    private let edge = EdgeView()
    private var splitTop: NSLayoutConstraint?
    private var overlayConstraints: [NSLayoutConstraint] = []
    private var edgeConstraints: [NSLayoutConstraint] = []
    private var overlayOffset: NSLayoutConstraint?
    private var overlayWidthConstraint: NSLayoutConstraint?
    private var overlayWidth: CGFloat
    private var isCompact = false
    private(set) var side: SidebarSide

    /// `background` and `overlayBackground` draw the Theme's gradient: under the whole window, and under the column
    /// while it is revealed over the page.
    init(background: NSView, overlayBackground: NSView, column: NSViewController, canvas: PageCanvasView,
         side: SidebarSide) {
        self.background = background
        self.column = column
        self.canvas = canvas
        self.side = side
        overlay = OverlayView(background: overlayBackground)
        overlayWidth = SafiraDesign.tokens.size.columnIdeal
        split.splitView = ClearDividerSplitView()
        split.splitView.isVertical = true
        columnItem = NSSplitViewItem(viewController: column)
        columnItem.minimumThickness = SafiraDesign.tokens.size.columnMin
        columnItem.maximumThickness = SafiraDesign.tokens.size.columnMax
        columnItem.holdingPriority = .defaultLow + 10
        columnItem.canCollapse = false
        let page = NSViewController()
        page.view = canvas
        pageItem = NSSplitViewItem(viewController: page)
        super.init(nibName: nil, bundle: nil)
        arrangeItems()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        view = NSView()
        for subview in [background, split.view] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
            let top = subview.topAnchor.constraint(equalTo: view.topAnchor)
            if subview === split.view { splitTop = top }
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                top,
                subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        addChild(split)
        edge.translatesAutoresizingMaskIntoConstraints = false
        edge.onPointerEntered = { [weak self] in self?.onPointerReachedEdge?() }
        edge.isHidden = true
        view.addSubview(edge)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onPointerExited = { [weak self] in self?.onPointerLeftSidebar?() }
        overlay.isHidden = true
        view.addSubview(overlay)
        let width = overlay.widthAnchor.constraint(equalToConstant: overlayWidth)
        overlayWidthConstraint = width
        NSLayoutConstraint.activate([
            edge.topAnchor.constraint(equalTo: view.topAnchor),
            edge.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: SafiraDesign.compactEdgeWidth),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            width,
        ])
        pinToSide()
    }

    /// The column and the page start at the window's top edge; while the window's buttons show, they step down by the
    /// title bar's height so that the buttons sit on a strip of their own.
    func setTopStrip(_ height: CGFloat, animated: Bool) {
        guard splitTop?.constant != height else { return }
        guard animated else {
            splitTop?.constant = height
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionRole.overlayFade.spec.duration.rawValue
            context.allowsImplicitAnimation = true
            splitTop?.animator().constant = height
            view.layoutSubtreeIfNeeded()
        }
    }

    /// True when the keyboard focus is inside the sidebar.
    var sidebarHasFocus: Bool {
        (view.window?.firstResponder as? NSView)?.isDescendant(of: column.view) == true
    }

    /// Moves the column to the other side; in Compact mode, the edge and the revealed column follow.
    func setSide(_ side: SidebarSide) {
        guard side != self.side else { return }
        self.side = side
        if !isCompact {
            let width = column.view.frame.width
            split.removeSplitViewItem(columnItem)
            split.removeSplitViewItem(pageItem)
            arrangeItems()
            setColumnWidth(width)
        }
        if isViewLoaded { pinToSide() }
    }

    func apply(_ presentation: SidebarPresentation, animated: Bool) {
        if presentation.isCompact != isCompact {
            isCompact = presentation.isCompact
            isCompact ? undock() : dock()
        }
        guard isCompact else { return }
        edge.isHidden = presentation.isRevealed
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        setOverlayShown(presentation.isRevealed, animated: shouldAnimate)
    }

    private func arrangeItems() {
        for item in side == .left ? [columnItem, pageItem] : [pageItem, columnItem] {
            split.addSplitViewItem(item)
        }
    }

    private func setColumnWidth(_ width: CGFloat) {
        guard width >= columnItem.minimumThickness else { return }
        view.layoutSubtreeIfNeeded()
        let position = side == .left ? width : split.splitView.bounds.width - width - split.splitView.dividerThickness
        split.splitView.setPosition(position, ofDividerAt: 0)
    }

    private func pinToSide() {
        NSLayoutConstraint.deactivate(edgeConstraints + overlayConstraints)
        let offset: NSLayoutConstraint
        if side == .left {
            edgeConstraints = [edge.leadingAnchor.constraint(equalTo: view.leadingAnchor)]
            offset = overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        } else {
            edgeConstraints = [edge.trailingAnchor.constraint(equalTo: view.trailingAnchor)]
            offset = overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        }
        overlayOffset = offset
        overlayConstraints = [offset]
        offset.constant = overlay.isHidden ? hiddenOffset : 0
        NSLayoutConstraint.activate(edgeConstraints + overlayConstraints)
    }

    /// Where the revealed column waits, just outside its edge of the window.
    private var hiddenOffset: CGFloat { side == .left ? -overlayWidth : overlayWidth }

    /// Takes the column out of the split and parks it, hidden, in the overlay.
    private func undock() {
        let width = column.view.frame.width
        if width >= columnItem.minimumThickness { overlayWidth = min(width, columnItem.maximumThickness) }
        split.removeSplitViewItem(columnItem)
        overlayWidthConstraint?.constant = overlayWidth
        overlayOffset?.constant = hiddenOffset
        overlay.host(column.view)
        addChild(column)
    }

    private func dock() {
        overlay.isHidden = true
        edge.isHidden = true
        overlayOffset?.constant = hiddenOffset
        column.view.removeFromSuperview()
        column.removeFromParent()
        split.insertSplitViewItem(columnItem, at: side == .left ? 0 : 1)
        setColumnWidth(overlayWidth)
    }

    private func setOverlayShown(_ shown: Bool, animated: Bool) {
        let target = shown ? 0 : hiddenOffset
        guard overlayOffset?.constant != target || overlay.isHidden == shown else { return }
        if shown { overlay.isHidden = false }
        guard animated else {
            overlayOffset?.constant = target
            overlay.isHidden = !shown
            return
        }
        let motion = shown ? MotionRole.panelAppear : MotionRole.panelDisappear
        NSAnimationContext.runAnimationGroup { context in
            context.duration = motion.spec.duration.rawValue
            context.allowsImplicitAnimation = true
            overlayOffset?.animator().constant = target
            view.layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.overlayOffset?.constant == target else { return }
                self.overlay.isHidden = !shown
            }
        }
    }
}

/// The split between the column and the page draws no divider line: the gradient runs under both.
private final class ClearDividerSplitView: NSSplitView {
    override var dividerColor: NSColor { .clear }

    override init(frame: NSRect) {
        super.init(frame: frame)
        dividerStyle = .thin
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}

/// The page in its canvas, as ThemeKit's `ContentCanvas` draws it (inset, rounded, outlined), in AppKit: the web view
/// is an AppKit view the canvas must clip, which a SwiftUI clip shape does not do for a hosted view. The banner floats
/// over the top of the canvas, and the Command bar over the whole page.
@MainActor
final class PageCanvasView: NSView {
    private let tokens = SafiraDesign.tokens
    private let clip = NSView()

    init(page: NSView, banner: NSView, commandBar: NSView) {
        super.init(frame: .zero)
        clip.wantsLayer = true
        clip.layer?.cornerRadius = tokens.radius.canvas
        clip.layer?.cornerCurve = .continuous
        clip.layer?.masksToBounds = true
        clip.layer?.borderWidth = tokens.size.stroke
        clip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clip)
        let inset = tokens.spacing.canvasInset
        NSLayoutConstraint.activate([
            clip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            clip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            clip.topAnchor.constraint(equalTo: topAnchor, constant: inset),
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
        updateOutline()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(accessibilityDisplayOptionsChanged(_:)),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateOutline()
    }

    @objc private func accessibilityDisplayOptionsChanged(_ notification: Notification) {
        updateOutline()
    }

    /// `.separator`, or `.secondary` under Increase Contrast, resolved in the view's appearance.
    private func updateOutline() {
        let color: NSColor = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            ? .secondaryLabelColor : .separatorColor
        effectiveAppearance.performAsCurrentDrawingAppearance { clip.layer?.borderColor = color.cgColor }
    }
}

/// A thin strip at the sidebar's edge that reports the pointer entering it.
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

/// Hosts the revealed column on its own gradient, and reports the pointer leaving it.
private final class OverlayView: NSView {
    var onPointerExited: (() -> Void)?

    init(background: NSView) {
        super.init(frame: .zero)
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)
        pin(background)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func host(_ content: NSView) {
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        pin(content)
    }

    private func pin(_ content: NSView) {
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExited?()
    }
}
