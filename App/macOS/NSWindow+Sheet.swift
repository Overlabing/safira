// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SwiftUI

extension NSWindow {
    /// A window for a sheet showing `view`. Sheets are never restored at launch: the window that asked for one rebuilds
    /// it when it needs it.
    static func sheet(_ view: some View) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.isRestorable = false
        return window
    }
}
