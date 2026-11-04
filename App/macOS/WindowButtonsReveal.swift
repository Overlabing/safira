// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import DesignKit

/// Hides the window's close, minimise and zoom buttons until the pointer reaches the window's top-left corner, as Zen
/// does: the column's first row and the page sit at the top edge, with no band for the buttons. In the corner the
/// buttons fade in (the kit's overlay fade; at once under Reduce Motion) and the content steps down a title bar's
/// height, so they sit on a strip of their own; leaving the corner hides them again. In full screen they stay, as the
/// system shows them. The corner stays at the top-left whichever side the sidebar is on.
@MainActor
final class WindowButtonsReveal {
    private weak var window: NSWindow?
    private weak var layout: BrowserWindowLayout?
    private let zone = HoverZone()
    private var isFullScreen = false
    private var isShown = true
    private var observers: [any NSObjectProtocol] = []

    init(window: NSWindow, layout: BrowserWindowLayout) {
        self.window = window
        self.layout = layout
        zone.translatesAutoresizingMaskIntoConstraints = false
        zone.onChange = { [weak self] inside in self?.setShown(inside, animated: true) }
        layout.view.addSubview(zone)
        let spacing = DesignTokens.Spacing.m
        let zoom = window.standardWindowButton(.zoomButton)?.frame.maxX ?? 0
        NSLayoutConstraint.activate([
            zone.leadingAnchor.constraint(equalTo: layout.view.leadingAnchor),
            zone.topAnchor.constraint(equalTo: layout.view.topAnchor),
            zone.widthAnchor.constraint(equalToConstant: zoom + spacing),
            zone.heightAnchor.constraint(equalToConstant: titleBarHeight),
        ])
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.setFullScreen(true) }
            },
            center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) {
                [weak self] _ in MainActor.assumeIsolated { self?.setFullScreen(false) }
            },
        ]
        setShown(false, animated: false)
    }

    private var buttons: [NSButton] {
        [.closeButton, .miniaturizeButton, .zoomButton].compactMap { window?.standardWindowButton($0) }
    }

    /// The title bar the buttons belong in: the window's frame above its content layout rectangle.
    private var titleBarHeight: CGFloat {
        guard let window else { return 0 }
        return window.frame.height - window.contentLayoutRect.height
    }

    private func setFullScreen(_ fullScreen: Bool) {
        isFullScreen = fullScreen
        zone.isHidden = fullScreen
        if fullScreen {
            buttons.forEach { $0.alphaValue = 1; $0.isHidden = false }
            layout?.setTopStrip(0, animated: false)
            isShown = true
        } else {
            setShown(false, animated: false)
        }
    }

    private func setShown(_ shown: Bool, animated: Bool) {
        guard !isFullScreen, shown != isShown || !animated else { return }
        isShown = shown
        let animate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        layout?.setTopStrip(shown ? titleBarHeight : 0, animated: animate)
        if shown { buttons.forEach { $0.isHidden = false } }
        guard animate else {
            buttons.forEach { $0.alphaValue = shown ? 1 : 0; $0.isHidden = !shown }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionRole.overlayFade.spec.duration.rawValue
            buttons.forEach { $0.animator().alphaValue = shown ? 1 : 0 }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isShown == shown else { return }
                self.buttons.forEach { $0.isHidden = !shown }
            }
        }
    }
}

/// The corner that reveals the buttons. It watches the pointer only: clicks go through to what lies under it.
private final class HoverZone: NSView {
    var onChange: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(false)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) { onChange?(true) }

    override func mouseExited(with event: NSEvent) { onChange?(false) }
}
