// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Observation
import ColorCore
import ColorUI
import DesignKit
import SafiraSession
import SwiftUI

/// What the banner over the page shows: nothing, or the offer that follows a link a Matching tab answered.
@MainActor
@Observable
final class MatchBannerModel {
    var banner: MatchBanner?
}

/// ThemeKit's banner, floating over the top of the page: the link was already open, and it can still open in a new Tab.
struct MatchBannerBar: View {
    let model: MatchBannerModel
    let theme: () -> Theme
    let openInNewTab: () -> Void
    let dismiss: () -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        if model.banner != nil {
            Banner(systemImage: "arrow.uturn.backward.circle",
                   message: String(localized: "This link was already open, so Safira showed that Tab.")) {
                Button("Open in New Tab", action: openInNewTab)
                    .controlSize(.small)
                IconButton(String(localized: "Dismiss"), systemImage: "xmark", action: dismiss)
            }
            .theme(theme())
            .accessibilityLabel(Text("Link already open"))
        }
    }
}

/// The banner's hosting view lets clicks beside the banner through to the page.
final class MatchBannerHostingView: NSHostingView<MatchBannerBar> {
    required init(rootView: MatchBannerBar) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}
