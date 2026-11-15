// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import AppKit
import Testing

/// #123: window full screen has no toolbar band, and leaving it gives the toolbar back as it was.
@Test func theToolbarHidesInFullScreenAndComesBackAsItWas() {
    var toolbar = FullScreenToolbar()
    #expect(!toolbar.isInFullScreen)
    #expect(toolbar.willEnter(toolbarVisible: true) == false)
    #expect(toolbar.isInFullScreen)
    #expect(toolbar.willExit() == true)
    #expect(!toolbar.isInFullScreen)
    #expect(toolbar.willExit() == nil)
}

@Test func aToolbarHiddenBeforeFullScreenStaysHiddenAfter() {
    var toolbar = FullScreenToolbar()
    #expect(toolbar.willEnter(toolbarVisible: false) == false)
    #expect(toolbar.willExit() == false)
}

/// A second "will enter" while entering (AppKit sends one per attempt) must not record the hidden toolbar as the one
/// to restore.
@Test func aRepeatedEnterKeepsTheFirstVisibility() {
    var toolbar = FullScreenToolbar()
    _ = toolbar.willEnter(toolbarVisible: true)
    #expect(toolbar.willEnter(toolbarVisible: false) == false)
    #expect(toolbar.willExit() == true)
}

/// The full screen still hides the menu bar and the toolbar until the pointer reaches the top, as macOS does.
@Test func fullScreenHidesTheMenuBarUntilThePointerReachesTheTop() {
    let options = SidebarFullScreen.options([.fullScreen])
    #expect(options == [.fullScreen, .autoHideToolbar, .autoHideMenuBar])
}
