// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Appearance
import Testing

/// Settings takes the card's place over the page, and going back gives the same page back: the page view never leaves
/// the window, so a web view in it does not reload.
@MainActor
@Suite struct PageCanvasPaneTests {
    let page = NSView()
    let banner = NSView()
    let commandBar = NSView()
    let pane = NSView()

    func canvas() -> PageCanvasView {
        let canvas = PageCanvasView(page: page, banner: banner, commandBar: commandBar)
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    @Test func aPaneFillsTheCardOverThePage() {
        let canvas = canvas()
        canvas.showPane(pane)
        canvas.layoutSubtreeIfNeeded()
        #expect(canvas.shownPane === pane)
        #expect(pane.isDescendant(of: canvas))
        #expect(pane.convert(pane.bounds, to: canvas) == canvas.cardFrame)
        #expect(!pane.isHiddenOrHasHiddenAncestor)
        #expect(page.isHiddenOrHasHiddenAncestor)
        #expect(banner.isHiddenOrHasHiddenAncestor)
        #expect(commandBar.isHiddenOrHasHiddenAncestor)
    }

    @Test func backKeepsThePage() {
        let canvas = canvas()
        let superview = page.superview
        canvas.showPane(pane)
        #expect(page.isDescendant(of: canvas))
        #expect(page.superview === superview)
        canvas.showPane(nil)
        #expect(canvas.shownPane == nil)
        #expect(pane.superview == nil)
        #expect(page.superview === superview)
        #expect(!page.isHiddenOrHasHiddenAncestor)
    }

    /// The banner shows and hides itself while a pane is over it; going back leaves it as it set itself.
    @Test func whatFloatsOverThePageKeepsItsOwnState() {
        let canvas = canvas()
        banner.isHidden = true
        canvas.showPane(pane)
        canvas.showPane(nil)
        #expect(banner.isHidden)
        #expect(!commandBar.isHiddenOrHasHiddenAncestor)
    }

    @Test func anotherPaneReplacesTheFirst() {
        let canvas = canvas()
        let other = NSView()
        canvas.showPane(pane)
        canvas.showPane(other)
        #expect(pane.superview == nil)
        #expect(canvas.shownPane === other)
        #expect(page.isHiddenOrHasHiddenAncestor)
    }
}
