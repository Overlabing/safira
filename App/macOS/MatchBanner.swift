// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Observation
import ColorCore
import ColorUI
import DesignKit
import SafiraSession
import SwiftUI
import UserFacing

/// What the banner over the page shows: nothing, an error shown as a banner (AppSupportKit's model), or the offer that
/// follows a link a Matching tab answered. The error comes first.
@MainActor
@Observable
final class MatchBannerModel {
    var banner: MatchBanner?
    var error: UserFacingError?

    var isEmpty: Bool { banner == nil && error == nil }
}

/// ThemeKit's banner, floating over the top of the page: an error that needs nothing from the user, or the link was
/// already open and it can still open in a new Tab.
struct MatchBannerBar: View {
    let model: MatchBannerModel
    let theme: () -> Theme
    let openInNewTab: () -> Void
    let dismiss: () -> Void
    let dismissError: () -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        if let error = model.error {
            Banner(systemImage: error.symbol, message: error.message) {
                IconButton(String(localized: "Dismiss", comment: "Banner shown after Safira focused a Tab that already had the link"), systemImage: "xmark", action: dismissError)
            }
            .theme(theme())
            .accessibilityLabel(Text(error.title))
        } else if model.banner != nil {
            Banner(systemImage: "arrow.uturn.backward.circle",
                   message: String(localized: "This link was already open, so Safira showed that Tab.", comment: "Banner shown after Safira focused a Tab that already had the link")) {
                Button("Open in New Tab", action: openInNewTab)
                    .controlSize(.small)
                IconButton(String(localized: "Dismiss", comment: "Banner shown after Safira focused a Tab that already had the link"), systemImage: "xmark", action: dismiss)
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
