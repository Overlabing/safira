// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin
import AppKit

/// The only way a test creates a window (`scripts/test-window-patterns.txt` guards it). The window is ordered in, so
/// WebKit and AppKit treat it as visible and neither throttles timers nor skips rendering, but it lies far left of every
/// display, never becomes key or main, and never activates the test process: the person using the Mac sees nothing.
@MainActor
public enum TestWindow {
    /// The left edge of every test window, beyond any arrangement of displays.
    public static let originX: CGFloat = -20_000

    /// A window of the given content size, ordered in off screen. `style` is for a test that needs a title bar (a
    /// toolbar, a full-size content view); it changes the layout, never what the user sees.
    public static func make(width: CGFloat, height: CGFloat, style: NSWindow.StyleMask = [.borderless]) -> NSWindow {
        let window = OffscreenWindow(contentRect: NSRect(x: originX, y: 0, width: width, height: height), styleMask: style,
                                     backing: .buffered, defer: false)
        // The initializer moves a titled window onto a display; once it exists, its frame is left alone.
        window.setFrameOrigin(NSPoint(x: originX, y: 0))
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.hasShadow = false
        window.orderFrontRegardless()
        return window
    }

    /// A window of the view's size, off screen, with the view as its content.
    public static func host(_ view: NSView, width: CGFloat, height: CGFloat,
                            style: NSWindow.StyleMask = [.borderless]) -> NSWindow {
        let window = make(width: width, height: height, style: style)
        window.contentView = view
        return window
    }
}

private final class OffscreenWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit would pull a titled window back onto a display.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
