// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore

/// Lays out the sidebar and the page. Docked, they sit side by side in a split view the user can resize. In Compact mode
/// the sidebar leaves the split, so the page takes the full width, and is drawn over the page while it is revealed.
/// The pointer is watched with AppKit tracking areas: SwiftUI's `onHover` is unreliable on a view hosted over a web view
/// (docs/architecture-v1.md §1.3).
@MainActor
final class SidebarLayoutViewController: NSViewController {
    /// The pointer left the revealed sidebar.
    var onPointerLeftSidebar: (() -> Void)?
    /// The pointer touched the left edge of the window in Compact mode.
    var onPointerReachedLeftEdge: (() -> Void)?

    private static let edgeWidth: CGFloat = 6
    private static let defaultOverlayWidth: CGFloat = 260

    private let sidebar: NSViewController
    private let split = NSSplitViewController()
    private let sidebarItem: NSSplitViewItem
    private let overlay = OverlayView()
    private let edge = EdgeView()
    private var overlayLeading: NSLayoutConstraint?
    private var overlayWidthConstraint: NSLayoutConstraint?
    private var overlayWidth = SidebarLayoutViewController.defaultOverlayWidth
    private var isCompact = false

    init(sidebar: NSViewController, page: NSViewController) {
        self.sidebar = sidebar
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 400
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(NSSplitViewItem(viewController: page))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        view = NSView()
        addChild(split)
        split.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(split.view)
        edge.translatesAutoresizingMaskIntoConstraints = false
        edge.onPointerEntered = { [weak self] in self?.onPointerReachedLeftEdge?() }
        view.addSubview(edge)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onPointerExited = { [weak self] in self?.onPointerLeftSidebar?() }
        overlay.isHidden = true
        view.addSubview(overlay)

        let leading = overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -overlayWidth)
        let width = overlay.widthAnchor.constraint(equalToConstant: overlayWidth)
        overlayLeading = leading
        overlayWidthConstraint = width
        NSLayoutConstraint.activate([
            split.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            split.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            split.view.topAnchor.constraint(equalTo: view.topAnchor),
            split.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            edge.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            edge.topAnchor.constraint(equalTo: view.topAnchor),
            edge.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            edge.widthAnchor.constraint(equalToConstant: Self.edgeWidth),
            leading,
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            width,
        ])
        edge.isHidden = true
    }

    /// True when the keyboard focus is inside the sidebar.
    var sidebarHasFocus: Bool {
        (view.window?.firstResponder as? NSView)?.isDescendant(of: sidebar.view) == true
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

    /// Takes the sidebar out of the split and parks it, hidden, in the overlay.
    private func undock() {
        let width = sidebar.view.frame.width
        if width >= sidebarItem.minimumThickness { overlayWidth = min(width, sidebarItem.maximumThickness) }
        split.removeSplitViewItem(sidebarItem)
        overlayWidthConstraint?.constant = overlayWidth
        overlayLeading?.constant = -overlayWidth
        overlay.host(sidebar.view)
        addChild(sidebar)
    }

    private func dock() {
        overlay.isHidden = true
        edge.isHidden = true
        overlayLeading?.constant = -overlayWidth
        sidebar.view.removeFromSuperview()
        sidebar.removeFromParent()
        split.insertSplitViewItem(sidebarItem, at: 0)
        view.layoutSubtreeIfNeeded()
        split.splitView.setPosition(overlayWidth, ofDividerAt: 0)
    }

    private func setOverlayShown(_ shown: Bool, animated: Bool) {
        let target = shown ? 0 : -overlayWidth
        guard overlayLeading?.constant != target || overlay.isHidden == shown else { return }
        if shown { overlay.isHidden = false }
        guard animated else {
            overlayLeading?.constant = target
            overlay.isHidden = !shown
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.allowsImplicitAnimation = true
            overlayLeading?.animator().constant = target
            view.layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.overlayLeading?.constant == target else { return }
                self.overlay.isHidden = !shown
            }
        }
    }
}

/// A thin strip at the left edge that reports the pointer entering it.
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

/// Hosts the revealed sidebar on its own material and reports the pointer leaving it.
private final class OverlayView: NSVisualEffectView {
    var onPointerExited: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .sidebar
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        shadow = NSShadow()
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 8
        layer?.masksToBounds = false
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
