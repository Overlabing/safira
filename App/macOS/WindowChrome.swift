// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit

/// The look shared by the Main window and the Private windows: no bar above the page, which sits inset in a thin frame
/// of one colour, the same colour as the sidebar's.
enum WindowChrome {
    /// A Private window's colour is the dark purple that marks it (see `PrivateSidebar`).
    static let privateFrame = NSColor(red: 0.20, green: 0.11, blue: 0.33, alpha: 1)
    /// Until Spaces carry a Theme, the Main window uses one quiet colour.
    static let mainFrame = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.17, green: 0.20, blue: 0.18, alpha: 1)
            : NSColor(red: 0.84, green: 0.87, blue: 0.85, alpha: 1)
    }

    static let pageInset: CGFloat = 6
    static let pageCornerRadius: CGFloat = 10
    /// The room the sidebar's top row leaves for the window's close, minimise and zoom buttons.
    static let trafficLightsWidth: CGFloat = 78

    /// The window's content reaches the top edge: the title bar is transparent and its title hidden. The title is still
    /// set, for the Window menu and for VoiceOver.
    static func apply(to window: NSWindow, frameColor: NSColor) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = frameColor
        window.isMovableByWindowBackground = true
    }
}

/// The page, inset with rounded corners inside a frame of the window's colour.
@MainActor
final class PageFrameView: NSView {
    init(frameColor: NSColor, page: NSView) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = frameColor.cgColor
        page.wantsLayer = true
        page.layer?.cornerRadius = WindowChrome.pageCornerRadius
        page.layer?.cornerCurve = .continuous
        page.layer?.masksToBounds = true
        page.translatesAutoresizingMaskIntoConstraints = false
        addSubview(page)
        let inset = WindowChrome.pageInset
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            page.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            page.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            page.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -inset),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // A dynamic colour resolves against the appearance in force when its CGColor is taken.
        if let color = window?.backgroundColor {
            effectiveAppearance.performAsCurrentDrawingAppearance { layer?.backgroundColor = color.cgColor }
        }
    }
}
