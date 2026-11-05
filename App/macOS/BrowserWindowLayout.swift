// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import DesignKit
import SafiraCore
import SwiftUI

/// The window shared by the Main window and Private windows: ThemeKit's sidebar in an AppKit window, as the kit's docs
/// set it up ("Sidebar", "In an AppKit window"). The Theme's gradient (`WindowBackground`) lies under the whole split;
/// the column is the system's sidebar split item (`NSSplitViewItem.sidebar(hosting:)`), flush with the window's edge,
/// in the system's sidebar material, dimmed by the system when the window is inactive; the page sits beside it in the
/// kit's detail card. In Compact mode the sidebar item collapses, and comes back from its edge of the window on demand.
/// The pointer is watched with AppKit tracking areas: SwiftUI's `onHover` is unreliable over a web view
/// (docs/architecture-v1.md §1.3).
@MainActor
final class BrowserWindowLayout: NSViewController {
    /// The pointer left the revealed sidebar.
    var onPointerLeftSidebar: (() -> Void)?
    /// The pointer touched the window's edge on the sidebar's side while the sidebar is collapsed in Compact mode.
    var onPointerReachedEdge: (() -> Void)?
    /// The system's sidebar button, or a divider dragged shut: the window decides what showing or hiding means.
    var onToggleSidebar: (() -> Void)?

    private let background: NSView
    private let column: NSViewController
    private let split = SidebarSplitController()
    private var columnItem: NSSplitViewItem
    private let pageItem: NSSplitViewItem
    private let edge = EdgeView()
    private let pointer = PointerWatch()
    private var edgeConstraints: [NSLayoutConstraint] = []
    private var collapseObservation: NSKeyValueObservation?
    private var isCompact = false
    /// What the layout wants the column to be; a change the split makes on its own is reported to the window.
    private var wantsCollapsed = false
    private(set) var side: SidebarSide

    /// `background` draws the Theme's gradient under the whole window; `column` is the sidebar's SwiftUI column, a `List`
    /// with `sidebarColumn(field:header:bottomBar:)`.
    init(background: NSView, column: some View, canvas: PageCanvasView, side: SidebarSide) {
        self.background = background
        self.side = side
        let item = NSSplitViewItem.sidebar(hosting: column, tokens: SafiraDesign.tokens)
        self.column = item.viewController
        columnItem = side == .left ? item : Self.item(for: side, holding: item.viewController)
        let page = NSViewController()
        page.view = canvas
        pageItem = NSSplitViewItem(viewController: page)
        super.init(nibName: nil, bundle: nil)
        split.onToggleSidebar = { [weak self] in self?.onToggleSidebar?() }
        configure(columnItem)
        arrangeItems()
        pointer.onExit = { [weak self] in self?.onPointerLeftSidebar?() }
        self.column.view.addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: pointer))
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
            edge.widthAnchor.constraint(equalToConstant: SafiraDesign.compactEdgeWidth),
        ])
        pinEdge()
    }

    /// True when the keyboard focus is inside the sidebar.
    var sidebarHasFocus: Bool {
        (view.window?.firstResponder as? NSView)?.isDescendant(of: column.view) == true
    }

    /// The toolbar items for the side the column is on: the system's sidebar button at the column's edge and the
    /// separator that follows its width (`NSSplitViewItem.sidebarToolbarItems`), or their inspector equivalents when the
    /// column is the trailing item.
    var toolbarItems: [NSToolbarItem.Identifier] {
        side == .left ? NSSplitViewItem.sidebarToolbarItems
                      : [.flexibleSpace, .inspectorTrackingSeparator, .flexibleSpace, .toggleInspector]
    }

    /// Moves the column to the other side of the window, keeping its width and whether it is collapsed.
    func setSide(_ side: SidebarSide) {
        guard side != self.side else { return }
        self.side = side
        let width = column.view.frame.width
        split.removeSplitViewItem(columnItem)
        split.removeSplitViewItem(pageItem)
        columnItem = Self.item(for: side, holding: column)
        configure(columnItem)
        columnItem.isCollapsed = wantsCollapsed
        arrangeItems()
        setColumnWidth(width)
        if isViewLoaded { pinEdge() }
    }

    func apply(_ presentation: SidebarPresentation, animated: Bool) {
        isCompact = presentation.isCompact
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
            }
        } else {
            columnItem.isCollapsed = collapsed
        }
    }

    /// The system's sidebar item on the left, as the kit makes it. A sidebar item belongs at the split's leading edge
    /// (its toolbar button and tracking separator follow the first divider), so on the right the column is the split's
    /// inspector item, the system's trailing column.
    private static func item(for side: SidebarSide, holding column: NSViewController) -> NSSplitViewItem {
        side == .left ? NSSplitViewItem(sidebarWithViewController: column)
                      : NSSplitViewItem(inspectorWithViewController: column)
    }

    /// The kit's widths for the column, whichever kind of split item holds it; only the window's own actions collapse it.
    private func configure(_ item: NSSplitViewItem) {
        let tokens = SafiraDesign.tokens
        item.minimumThickness = tokens.size.columnMin
        item.maximumThickness = tokens.size.columnMax
        item.canCollapse = true
        item.canCollapseFromWindowResize = false
        item.holdingPriority = .defaultLow + 10
        let observed = ObjectIdentifier(item)
        collapseObservation = item.observe(\.isCollapsed) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, ObjectIdentifier(self.columnItem) == observed,
                      self.columnItem.isCollapsed != self.wantsCollapsed else { return }
                self.onToggleSidebar?()
            }
        }
    }

    private func arrangeItems() {
        for item in side == .left ? [columnItem, pageItem] : [pageItem, columnItem] {
            split.addSplitViewItem(item)
        }
    }

    private func setColumnWidth(_ width: CGFloat) {
        guard width >= columnItem.minimumThickness, !columnItem.isCollapsed else { return }
        view.layoutSubtreeIfNeeded()
        let position = side == .left ? width : split.splitView.bounds.width - width - split.splitView.dividerThickness
        split.splitView.setPosition(position, ofDividerAt: 0)
    }

    private func pinEdge() {
        NSLayoutConstraint.deactivate(edgeConstraints)
        edgeConstraints = [side == .left ? edge.leadingAnchor.constraint(equalTo: view.leadingAnchor)
                                         : edge.trailingAnchor.constraint(equalTo: view.trailingAnchor)]
        NSLayoutConstraint.activate(edgeConstraints)
    }
}

/// The system's sidebar and inspector buttons send `toggleSidebar(_:)` and `toggleInspector(_:)` to the split view
/// controller, which would collapse the column behind the window's back: the window decides instead, so that the
/// button and Compact mode stay one state.
private final class SidebarSplitController: NSSplitViewController {
    var onToggleSidebar: (() -> Void)?

    override func toggleSidebar(_ sender: Any?) {
        onToggleSidebar?()
    }

    override func toggleInspector(_ sender: Any?) {
        onToggleSidebar?()
    }
}

/// The page in the kit's detail card (`SidebarDetail`), in AppKit: the web view is an AppKit view the card must clip,
/// which a SwiftUI clip shape does not do for a hosted view. Inset `Spacing.canvasInset` from the detail's edges and from
/// the window's top edge, under the transparent toolbar; on the plain background, rounded `Radius.canvas`, with a 1 pt
/// `.separator` line on its edge.
/// The banner floats over the top of the card, and the Command bar over the whole page.
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

/// The toolbar of a window with the kit's sidebar: the items the layout asks for, icons only, no title.
@MainActor
final class SidebarToolbar: NSObject, NSToolbarDelegate {
    private let items: () -> [NSToolbarItem.Identifier]

    init(items: @escaping () -> [NSToolbarItem.Identifier]) {
        self.items = items
    }

    /// A new toolbar for the window, with the items in force: they change with the sidebar's side.
    func install(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: "Safira.sidebar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        items()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        items()
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        nil
    }

    /// On the right the column is the split's inspector item, but it is still the sidebar: its button says so to
    /// VoiceOver and in its help tag, as the system's sidebar button does on the left.
    func toolbarWillAddItem(_ notification: Notification) {
        guard let item = notification.userInfo?["item"] as? NSToolbarItem, item.itemIdentifier == .toggleInspector
        else { return }
        let title = String(localized: "Sidebar", comment: "Toolbar: the button that hides and shows the sidebar on the right")
        item.label = title
        item.toolTip = title
    }
}

/// The full screen shows the toolbar only while the pointer is at the top of the screen, as the kit's
/// `sidebarWindowChrome()` does in SwiftUI.
enum SidebarFullScreen {
    static func options(_ proposed: NSApplication.PresentationOptions) -> NSApplication.PresentationOptions {
        proposed.union([.autoHideToolbar, .autoHideMenuBar])
    }
}

/// Reports the pointer leaving the column's view: the owner of its tracking area.
private final class PointerWatch: NSResponder {
    var onExit: (() -> Void)?

    override func mouseExited(with event: NSEvent) {
        onExit?()
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
