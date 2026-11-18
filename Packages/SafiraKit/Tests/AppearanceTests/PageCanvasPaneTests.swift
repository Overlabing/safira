// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Appearance
import DesignKit
import SwiftUI
import Testing

/// The Library pushes the page's card toward the trailing edge, at its own size, with a strip in sight that goes back
/// when clicked; closing it gives the same page back. The page view never leaves the window, so a web view in it does
/// not reload.
@MainActor
@Suite struct PageCanvasPaneTests {
    let page = NSView()

    func canvas() -> PageCanvasView {
        let canvas = PageCanvasView(page: page, banner: NSView(), commandBar: NSView())
        canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        canvas.layoutSubtreeIfNeeded()
        return canvas
    }

    @Test func thePushMovesTheCardAtItsOwnSize() {
        let canvas = canvas()
        let before = canvas.cardFrame
        canvas.setPush(500, animated: false)
        canvas.layoutSubtreeIfNeeded()
        #expect(canvas.push == 500)
        #expect(canvas.cardFrame.minX == before.minX + 500)
        #expect(canvas.cardFrame.width == before.width)
        canvas.setPush(0, animated: false)
        canvas.layoutSubtreeIfNeeded()
        #expect(canvas.cardFrame == before)
    }

    @Test func thePeekCoverGoesBackWhenClicked() {
        let canvas = canvas()
        var clicks = 0
        canvas.showPeek(label: "Back to Example", hint: "Click the page to go back") { clicks += 1 }
        #expect(canvas.showsPeek)
        canvas.pressPeek()
        #expect(clicks == 1)
        canvas.showPeek(label: nil)
        #expect(!canvas.showsPeek)
        #expect(page.isDescendant(of: canvas))
    }

    @Test func theLibraryCoversTheColumnAndClosingGivesThePageBack() {
        let canvas = canvas()
        let layout = BrowserWindowLayout(background: NSView(), column: Color.clear, canvas: canvas)
        layout.view.frame = NSRect(x: 0, y: 0, width: 1200, height: 700)
        layout.view.layoutSubtreeIfNeeded()
        let card = canvas.convert(canvas.cardFrame, to: layout.view)
        let library = NSView()

        layout.showLibrary(library, animated: false)
        layout.view.layoutSubtreeIfNeeded()

        #expect(layout.isLibraryShown)
        #expect(library.frame.minX == 0)
        #expect(library.frame.width == 1200 - DesignTokens.standard.size.libraryPeek)
        let pushed = canvas.convert(canvas.cardFrame, to: layout.view)
        #expect(pushed.width == card.width)
        // The card starts the canvas inset past the Library, so the peek is `Size.libraryPeek` less that inset. Within
        // 1 pt: the split's thin divider (1 pt) sits between the column and the page and is not part of either.
        #expect(abs(pushed.minX - (library.frame.maxX + DesignTokens.standard.spacing.canvasInset)) <= 1)
        #expect(page.isDescendant(of: canvas))

        layout.hideLibrary(animated: false)
        layout.view.layoutSubtreeIfNeeded()

        #expect(!layout.isLibraryShown)
        #expect(library.isHidden)
        #expect(canvas.convert(canvas.cardFrame, to: layout.view) == card)
        #expect(page.isDescendant(of: canvas))
    }
}
