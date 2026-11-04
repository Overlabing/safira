// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import DesignKit

/// The only values Safira adds to ThemeKit's design kit: what a browser has and the kit does not (the floating Command
/// bar, the edge that reveals the sidebar, window sizes). Every other spacing, radius, size, opacity and duration is a
/// `DesignTokens.standard` or `MotionRole` value, read where it is used.
enum SafiraDesign {
    static let tokens = DesignTokens.standard

    // MARK: Command bar

    /// The floating Command bar: a fixed width, so the glass does not move while suggestions come and go.
    static let commandBarWidth: CGFloat = 600
    /// Its top, as a share of the page's height: in the upper third, like Spotlight and the ⌘K palettes.
    static let commandBarTopFraction: CGFloat = 0.18
    /// Concentric to the suggestion rows inside it, which sit `Spacing.s` from its edge.
    static var commandBarRadius: CGFloat { tokens.radius.row + DesignTokens.Spacing.s }
    /// A veil of the window background under the glass: the page behind it can be any colour.
    static let commandBarVeil: Double = 0.35
    /// It never comes closer than this to the page's sides.
    static var commandBarSideMargin: CGFloat { tokens.spacing.pillFloat }

    // MARK: Window

    /// The strip at the sidebar's edge of the window that brings the sidebar back in Compact mode.
    static let compactEdgeWidth: CGFloat = 6
    static let mainWindowSize = NSSize(width: 1200, height: 800)
    static let privateWindowSize = NSSize(width: 1100, height: 760)
    /// How far a new Private window sits from the one it was opened from.
    static let privateWindowCascade: CGFloat = 28
    /// How long the Matching tab banner stays before it goes by itself.
    static let matchBannerLifetime: Duration = .seconds(12)
}
