// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import DesignKit
import SafiraCore
import SwiftUI

/// The downloads button of the sidebar's footer: an arrow in a ring that fills with the combined progress while
/// downloads run, a count when more than one runs, a bounce when one finishes, a dot when one failed. The caller hides
/// it when `DownloadsIndicator.isVisible` is false.
public struct DownloadsButton: View {
    @Environment(\.designTokens) private var tokens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let indicator: DownloadsIndicator
    private let action: () -> Void
    @State private var isBouncing: Bool
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    public init(indicator: DownloadsIndicator, action: @escaping () -> Void) {
        self.init(indicator: indicator, isBouncing: false, action: action)
    }

    /// `isBouncing` holds the bounce at its peak, for the design renders.
    init(indicator: DownloadsIndicator, isBouncing: Bool, action: @escaping () -> Void) {
        self.indicator = indicator
        self.action = action
        _isBouncing = State(initialValue: isBouncing)
    }

    public var body: some View {
        let side = max(tokens.size.toolbarButton, tokens.size.minTarget)
        let shape = RoundedRectangle(cornerRadius: tokens.radius.row, style: .continuous)
        WithColorRoles { roles in
            Button(action: action) {
                ZStack {
                    if indicator.runningCount > 0 {
                        ProgressRing(fraction: indicator.fraction, track: roles.railDivider, fill: roles.selectionMarker)
                    }
                    Image(systemName: "arrow.down")
                        .font(.system(size: tokens.size.smallTile / 2, weight: .semibold))
                        .foregroundStyle(indicator.runningCount > 0 ? roles.tintText : roles.secondaryText)
                }
                .frame(width: tokens.size.smallTile, height: tokens.size.smallTile)
                .offset(y: isBouncing ? -DesignTokens.Spacing.xs : 0)
                .frame(width: side, height: side)
                .overlay(alignment: .topTrailing) { mark(roles) }
                .background { if isHovered { shape.fill(roles.hoverFill) } }
                .focusRing(isFocused, in: shape)
                .contentShape(.rect)
            }
            .buttonStyle(PressedOpacityStyle())
            .focused($isFocused)
            .focusEffectDisabled()
            .onHover { isHovered = $0 }
            .help(help)
            .accessibilityLabel(Text("Downloads", tableName: "DownloadsUI", bundle: .module, comment: "Downloads button"))
            .accessibilityValue(DownloadText.value(of: indicator))
        }
        .onChange(of: indicator.finishedCount) { old, new in
            guard new > old, !reduceMotion else { return }
            withAnimation(MotionRole.rowState.animation(reduceMotion: false)) { isBouncing = true } completion: {
                withAnimation(MotionRole.panelAppear.animation(reduceMotion: false)) { isBouncing = false }
            }
        }
    }

    @ViewBuilder
    private func mark(_ roles: ColorRoles) -> some View {
        if indicator.needsAttention {
            Circle()
                .fill(Color(nsColor: .systemRed))
                .frame(width: tokens.size.dot, height: tokens.size.dot)
                .padding(DesignTokens.Spacing.xxs)
                .accessibilityHidden(true)
        } else if indicator.runningCount > 1 {
            Text(verbatim: "\(indicator.runningCount)")
                .role(tokens.type.glyphCircleSmall)
                .monospacedDigit()
                .foregroundStyle(roles.bandText)
                .padding(.horizontal, DesignTokens.Spacing.xs)
                .frame(minWidth: tokens.size.glyphCircleSmall, minHeight: tokens.size.glyphCircleSmall)
                .background(Capsule().fill(roles.bandFill))
                .offset(x: DesignTokens.Spacing.xxs, y: -DesignTokens.Spacing.xxs)
                .accessibilityHidden(true)
        }
    }

    private var help: String {
        String(localized: "Downloads: \(DownloadText.value(of: indicator))", table: "DownloadsUI", bundle: .module,
               comment: "Downloads button: its help tag")
    }
}

/// A ring round the arrow: the track, and over it the combined progress from the top, clockwise. With no size known it
/// shows a quarter of the ring, turning unless Reduce Motion is on.
private struct ProgressRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let fraction: Double?
    let track: Color
    let fill: Color
    @State private var turning = false

    var body: some View {
        let width = DesignTokens.Spacing.xxs
        ZStack {
            Circle().stroke(track, lineWidth: width)
            Circle()
                .trim(from: 0, to: fraction.map { max(0.02, $0) } ?? 0.25)
                .stroke(fill, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90 + (fraction == nil && turning ? 360 : 0)))
        }
        .padding(width / 2)
        .onAppear {
            guard fraction == nil, !reduceMotion else { return }
            withAnimation(.linear(duration: MotionDuration.cycle.rawValue).repeatForever(autoreverses: false)) {
                turning = true
            }
        }
    }
}
