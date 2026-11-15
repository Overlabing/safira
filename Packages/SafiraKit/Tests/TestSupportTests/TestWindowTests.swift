// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin
import AppKit
import TestSupport
import Testing

/// A test window is ordered in, so WebKit renders into it, yet it lies on no display and never takes the keyboard.
@MainActor
@Suite struct TestWindowTests {
    @Test(arguments: [NSWindow.StyleMask.borderless, [.titled, .closable, .resizable, .fullSizeContentView]])
    func aTestWindowIsOrderedInOnNoDisplayAndNeverKeyOrMain(style: NSWindow.StyleMask) {
        let window = TestWindow.host(NSView(), width: 400, height: 300, style: style)
        defer { window.close() }
        window.makeKeyAndOrderFront(nil)
        window.setContentSize(NSSize(width: 1200, height: 800))

        #expect(window.isVisible == true)
        #expect(window.frame.minX == -20_000)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) } == true)
        #expect(window.canBecomeKey == false)
        #expect(window.canBecomeMain == false)
        #expect(window.isKeyWindow == false)
        #expect(window.isMainWindow == false)
        #expect(NSApplication.shared.isActive == false)
    }
}
