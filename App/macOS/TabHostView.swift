// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import DesignKit
import SwiftUI

/// Shows one page at a time. Swapping only moves views in and out of the window: the pages stay alive in the
/// Profile's registry, so none reloads.
@MainActor
final class TabHostView: NSView {
    private lazy var emptyPage = NSHostingView(rootView: EmptyPage())
    private var shown: NSView?

    func show(_ page: NSView?) {
        let next = page ?? emptyPage
        guard next !== shown else { return }
        let focusWasInPage = shown.map { previous in
            (window?.firstResponder as? NSView)?.isDescendant(of: previous) == true
        } ?? false
        shown?.removeFromSuperview()
        next.frame = bounds
        next.autoresizingMask = [.width, .height]
        addSubview(next)
        shown = next
        if focusWasInPage, page != nil {
            window?.makeFirstResponder(next)
        }
    }
}

private struct EmptyPage: View {
    @Environment(\.designTokens) private var tokens

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            Text("Type an address or a search")
                .font(.title2)
            Text("Press ⌘L to go to the Command bar.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
