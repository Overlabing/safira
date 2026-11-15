// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Appearance
import DesignKit
import Testing

/// The page's card sits the kit's canvas inset (12 pt) from every side of the area beside the sidebar.
@MainActor
@Test func thePageCardKeepsTheCanvasInsetOnAllFourSides() {
    #expect(DesignTokens.standard.spacing.canvasInset == 12)
    let canvas = PageCanvasView(page: NSView(), banner: NSView(), commandBar: NSView())
    canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    canvas.layoutSubtreeIfNeeded()
    let card = canvas.cardFrame
    #expect(card.minX == 12)
    #expect(canvas.bounds.maxX - card.maxX == 12)
    #expect(card.minY == 12)
    #expect(canvas.bounds.maxY - card.maxY == 12)
}
