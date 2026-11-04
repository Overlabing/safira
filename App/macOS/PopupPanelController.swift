// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Observation
import SafiraCore
import SafiraSession
import WebKit

/// The floating panel of a popup (a sign-in, a payment), attached to the Main window. Its title is the host the popup
/// is on, which a page cannot change: the page's own title is only its subtitle. The panel goes away when the popup
/// ends, and the user closing it ends the popup.
@MainActor
final class PopupPanelController: NSObject, NSWindowDelegate {
    private let popup: Popup
    private let panel: NSPanel
    private let close: (PopupID) -> Void
    private let onEnd: (PopupID) -> Void
    private weak var parent: NSWindow?

    init(popup: Popup, webView: WKWebView, close: @escaping (PopupID) -> Void, onEnd: @escaping (PopupID) -> Void) {
        self.popup = popup
        self.close = close
        self.onEnd = onEnd
        let size = popup.requestedWindow.panelSize
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow],
                        backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = webView
        panel.delegate = self
        panel.setAccessibilityLabel(String(localized: "Sign-in window"))
        updateTitle()
        track()
    }

    /// Attaches the panel to the Main window, centred over it, or detaches it while the Tab that opened it is not shown.
    func setVisible(_ visible: Bool, over window: NSWindow?) {
        guard !popup.isClosed else { return }
        if visible, let window {
            guard parent !== window || !panel.isVisible else { return }
            parent = window
            window.addChildWindow(panel, ordered: .above)
            let frame = window.frame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.midY - panel.frame.height / 2 + 40))
            panel.makeKeyAndOrderFront(nil)
        } else if panel.isVisible || parent != nil {
            parent?.removeChildWindow(panel)
            parent = nil
            panel.orderOut(nil)
        }
    }

    private func updateTitle() {
        panel.title = popup.state.url?.host() ?? String(localized: "Loading…")
        panel.subtitle = popup.state.title ?? ""
    }

    private func track() {
        withObservationTracking {
            _ = (popup.state, popup.isClosed)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.popup.isClosed {
                    self.end()
                } else {
                    self.updateTitle()
                    self.track()
                }
            }
        }
    }

    private func end() {
        panel.delegate = nil
        parent?.removeChildWindow(panel)
        panel.contentView = nil
        panel.orderOut(nil)
        onEnd(popup.id)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close(popup.id)
        return false
    }
}
