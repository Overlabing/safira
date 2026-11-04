// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Observation
import SafiraSession
import SwiftUI

/// What the banner under the toolbar shows: nothing, or the offer that follows a link a Matching tab answered.
@MainActor
@Observable
final class MatchBannerModel {
    var banner: MatchBanner?
}

/// The discreet bar that says a link was already open and offers to open it in a new Tab anyway.
struct MatchBannerBar: View {
    let model: MatchBannerModel
    let openInNewTab: () -> Void
    let dismiss: () -> Void

    var body: some View {
        if model.banner != nil {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("This link was already open, so Safira showed that Tab.")
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button("Open in New Tab", action: openInNewTab)
                    .controlSize(.small)
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss"))
                .help("Dismiss")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Link already open"))
        }
    }
}
