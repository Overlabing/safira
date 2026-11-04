// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import ColorCore
import ColorPlatform

/// Where the sidebar's text sits, described for ThemeKit's legibility solver, and the Profile band the Active profile
/// is recognised by. The solver does not know the layout; these are Safira's own numbers. ThemeKit's default dark
/// gradient and washes were measured against them and fail for the bright hues (mint, teal, orange): white label text
/// on them stays under 4.5:1, which no solved alpha or mix can repair, so the dark numbers here are thinner.
public enum SidebarSurfaces {
    /// The gradient the sidebar draws for a Theme. Increase Contrast thins it, so the text sits on something closer to
    /// the plain window.
    public static func gradient(in appearance: Appearance) -> GradientSpec {
        let base: GradientSpec = appearance.isDark
            ? GradientSpec(top: 0.30, middle: 0.13, bottom: 0.04)
            : GradientSpec(top: 0.38, middle: 0.16, bottom: 0.05)
        guard appearance.isIncreasedContrast else { return base }
        return GradientSpec(top: base.top * 0.75, middle: base.middle * 0.75, bottom: base.bottom * 0.75)
    }

    /// The sidebar column: the Space's gradient under everything, the Tab list from about the top eighth of the window
    /// down (the Profile band and the Space title sit above it), the washes of a hovered and a current row in the
    /// primary hue, the selected row, and the fills a tinted text (a badge) stands on.
    public static func surfaces(in appearance: Appearance) -> Surfaces {
        Surfaces(
            gradient: gradient(in: appearance),
            contentTop: 0.12,
            fills: appearance.isDark ? [0.06, 0.10] : [0.08, 0.12],
            selection: appearance.isDark
                ? .init(floor: 0.18, cap: 0.5, visibility: 1.15) : .init(floor: 0.22, cap: 0.5, visibility: 1.2),
            tintFills: [0.14, 0.25])
    }

    /// What it takes to keep the sidebar's label, secondary label and tinted text at 4.5:1 on the Theme's gradient.
    public static func legibility(of theme: Theme, in appearance: Appearance) -> Legibility {
        Legibility.of(theme, surfaces: surfaces(in: appearance), in: appearance)
    }

    /// The flat fill of the Profile band under the Profile switcher: the Profile's primary hue, opaque. Far stronger than
    /// any Space gradient, so a Profile reads as more distinct than a Space.
    public static func profileBandColor(of theme: Theme, in appearance: Appearance) -> RGBA {
        ResolvedColors(theme, in: appearance).primary
    }

    /// The text colour on the band, black or white, whichever contrasts more: on one opaque colour the better of the two
    /// is never under 4.58:1.
    public static func profileBandInk(of theme: Theme, in appearance: Appearance) -> RGBA {
        let band = profileBandColor(of: theme, in: appearance)
        return Contrast.ratio(.white, band) >= Contrast.ratio(.black, band) ? .white : .black
    }

    public static func profileBandContrast(of theme: Theme, in appearance: Appearance) -> Double {
        Contrast.ratio(profileBandInk(of: theme, in: appearance), profileBandColor(of: theme, in: appearance))
    }
}
