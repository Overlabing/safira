// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import ColorCore
import ColorPlatform

/// The Dock icon of a Profile: Safira's mark on a squircle in the Profile's two hues, so the Active profile is told
/// apart in the Dock and the app switcher as well as in the sidebar.
public enum DockIcon {
    /// The icon for a Theme, drawn on demand at any size. The squircle sits inside the icon grid's margin, as macOS app
    /// icons do.
    @MainActor
    public static func image(for theme: Theme, size: CGFloat = 512) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let body = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)
            let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
            NSGradient(starting: theme.primary.systemColor, ending: theme.secondary.systemColor)?
                .draw(in: shape, angle: -45)
            let glyph = NSAttributedString(string: "S", attributes: [
                .font: NSFont.systemFont(ofSize: body.height * 0.6, weight: .bold),
                .foregroundColor: NSColor.white,
            ])
            let box = glyph.size()
            glyph.draw(at: NSPoint(x: body.midX - box.width / 2, y: body.midY - box.height / 2))
            return true
        }
        return image
    }
}
