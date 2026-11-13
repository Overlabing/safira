// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import AppKit
import DesignKit
import SwiftUI

extension TabHostView {
    /// The page host of a window: with no page, it asks for an address.
    static func withEmptyPage() -> TabHostView {
        TabHostView(emptyPage: NSHostingView(rootView: EmptyPage()))
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
