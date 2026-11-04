// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Appearance
import ColorCore
import Testing

@MainActor
@Suite struct DockIconTests {
    private func pixels(_ theme: Theme) throws -> NSBitmapImageRep {
        let image = DockIcon.image(for: theme, size: 128)
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 128, pixelsHigh: 128,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: 128, height: 128))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    @Test func theIconIsASquircleInsideTheGridMargin() throws {
        let bitmap = try pixels(#require(ThemeCatalog.theme(id: "teal-green")))

        #expect(bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0)
        #expect(bitmap.colorAt(x: 20, y: 64)?.alphaComponent == 1)
    }

    @Test func twoProfilesWithDifferentPalettesHaveDifferentIcons() throws {
        let work = try pixels(#require(ThemeCatalog.theme(id: "indigo-blue")))
        let personal = try pixels(#require(ThemeCatalog.theme(id: "orange-pink")))

        #expect(work.colorAt(x: 20, y: 64) != personal.colorAt(x: 20, y: 64))
        #expect(work.colorAt(x: 108, y: 64) != personal.colorAt(x: 108, y: 64))
    }

    @Test func theSameThemeAlwaysDrawsTheSameIcon() throws {
        let theme = try #require(ThemeCatalog.theme(id: "purple-pink"))

        #expect(try pixels(theme).representation(using: .png, properties: [:])
            == pixels(theme).representation(using: .png, properties: [:]))
    }
}
