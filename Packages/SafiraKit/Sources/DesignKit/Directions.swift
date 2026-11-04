// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SwiftUI
import ThemeStandIn

// The three candidate directions. They share the spacing scale, the motion roles and the accessibility fallbacks, and
// differ in where glass sits, how strong the frame is, and how dense the column reads.
extension DesignTokens {
    public static let all: [DesignTokens] = [.quietGlass, .deepGlass, .slimFrame]

    /// Glass only on controls (the pill, the switcher, floating panels); the column sits straight on a calm gradient.
    public static let quietGlass = DesignTokens(
        name: "Quiet Glass",
        spacing: Spacing(
            listMargin: Spacing.m, rowGap: Spacing.xs, rowInsetVertical: Spacing.xs, rowInsetHorizontal: Spacing.s,
            sectionHeaderBottom: 6, tileToText: Spacing.s, glassMerge: 6, pageInset: Spacing.s, groupGap: Spacing.m,
            panelFieldVertical: Spacing.m, panelFieldHorizontal: Spacing.l, panelInset: Spacing.s,
            bannerVertical: 6, bannerHorizontal: Spacing.m, sheetMargin: Spacing.xl),
        radius: Radius(tile: 5, row: 8, pill: nil, page: 12, panel: 16, column: 0, banner: nil, sheet: 16),
        emphasis: Emphasis(
            hover: 0.10, hoverLiftLight: 0.10, selectedDark: 0.25, selectedLight: 0.30, selectedLightBrightHue: 0.48, glassTint: 0.35,
            layer: 0.06, tileFill: 0.25, increasedContrastFactor: 1.8, panelVeil: 0.35, scrim: 0.10, pageShadow: 0.10,
            panelGlow: 0),
        size: Size(
            row: 32, tile: 20, glyph: 12, pill: 34, toolbarButton: Size.minTarget, switcherItem: 36, switcherHeight: 36,
            columnWidth: 264, panelWidth: 600, panelRow: 36, panelTopFraction: 0.18, sheetWidth: 400, selectionBar: 0),
        type: TypeScale(
            row: TextRole(.body), rowSelected: TextRole(.body, .semibold),
            sectionHeader: TextRole(.caption, .semibold, tracking: 0.6, uppercased: true),
            columnTitle: TextRole(.headline), pill: TextRole(.callout), panelField: TextRole(.title3),
            panelTitle: TextRole(.body), panelDetail: TextRole(.body), panelAction: TextRole(.callout, .medium),
            banner: TextRole(.callout), sheetTitle: TextRole(.headline), sheetBody: TextRole(.callout),
            switcherLabel: TextRole(.callout, .semibold)),
        materials: Materials(
            column: .none, pill: .glass(tint: 0), switcher: .glass(tint: 0), panel: .glass(tint: 0),
            banner: .glass(tint: 0), selection: .tint),
        frame: FrameStyle(light: .light, dark: .dark, axis: .vertical, glow: 0))

    /// The whole column is one glass panel floating over a richer, diagonal gradient; larger radii, a coloured glow.
    public static let deepGlass = DesignTokens(
        name: "Deep Glass",
        spacing: Spacing(
            listMargin: Spacing.m, rowGap: Spacing.xs, rowInsetVertical: Spacing.xs, rowInsetHorizontal: Spacing.s,
            sectionHeaderBottom: 6, tileToText: Spacing.s, glassMerge: 6, pageInset: Spacing.m, groupGap: Spacing.m,
            panelFieldVertical: Spacing.l, panelFieldHorizontal: Spacing.l, panelInset: Spacing.s,
            bannerVertical: Spacing.s, bannerHorizontal: Spacing.l, sheetMargin: Spacing.xl),
        radius: Radius(tile: 6, row: 10, pill: 12, page: 16, panel: 22, column: 20, banner: nil, sheet: 22),
        emphasis: Emphasis(
            hover: 0.12, hoverLiftLight: 0.12, selectedDark: 0.35, selectedLight: 0.32, selectedLightBrightHue: 0.50, glassTint: 0.35,
            layer: 0.08, tileFill: 0.25, increasedContrastFactor: 1.8, panelVeil: 0, scrim: 0.18, pageShadow: 0.22,
            panelGlow: 0.45),
        size: Size(
            row: 34, tile: 22, glyph: 12, pill: 36, toolbarButton: Size.minTarget, switcherItem: 36, switcherHeight: 40,
            columnWidth: 272, panelWidth: 640, panelRow: 40, panelTopFraction: 0.18, sheetWidth: 420, selectionBar: 0),
        type: TypeScale(
            row: TextRole(.body), rowSelected: TextRole(.body, .semibold),
            sectionHeader: TextRole(.caption, .semibold, tracking: 0.6, uppercased: true),
            columnTitle: TextRole(.title3, .semibold), pill: TextRole(.body, .medium),
            panelField: TextRole(.title2), panelTitle: TextRole(.body, .medium), panelDetail: TextRole(.body),
            panelAction: TextRole(.callout, .medium), banner: TextRole(.callout, .medium),
            sheetTitle: TextRole(.title3, .semibold), sheetBody: TextRole(.body), switcherLabel: TextRole(.callout, .semibold)),
        materials: Materials(
            column: .glass(tint: 0.10), pill: .layer, switcher: .glass(tint: 0), panel: .glass(tint: 0.08),
            banner: .glass(tint: 0.20), selection: .tint),
        frame: FrameStyle(
            light: GradientSpec(top: 0.62, middle: 0.34, bottom: 0.16),
            dark: GradientSpec(top: 0.70, middle: 0.40, bottom: 0.18),
            axis: .diagonal, glow: 0.45))

    /// A thin, flat frame and a tight column: smaller rows, no section labels, a neutral lifted selection; glass kept
    /// for what floats (switcher, floating panels, banners).
    public static let slimFrame = DesignTokens(
        name: "Slim Frame",
        spacing: Spacing(
            listMargin: Spacing.m, rowGap: Spacing.xs, rowInsetVertical: Spacing.xs, rowInsetHorizontal: Spacing.s,
            sectionHeaderBottom: 6, tileToText: Spacing.s, glassMerge: 6, pageInset: Spacing.xs,
            groupGap: Spacing.s, panelFieldVertical: Spacing.m, panelFieldHorizontal: Spacing.m, panelInset: Spacing.xs,
            bannerVertical: Spacing.xs, bannerHorizontal: Spacing.m, sheetMargin: Spacing.l),
        radius: Radius(tile: 5, row: 8, pill: 8, page: 10, panel: 12, column: 0, banner: 8, sheet: 12),
        emphasis: Emphasis(
            hover: 0.10, hoverLiftLight: 0.10, selectedDark: 0.25, selectedLight: 0.30, selectedLightBrightHue: 0.48,
            glassTint: 0.35, layer: 0.07, tileFill: 0.25, increasedContrastFactor: 1.8, panelVeil: 0.55, scrim: 0.25,
            pageShadow: 0, panelGlow: 0),
        size: Size(
            row: 32, tile: 20, glyph: 12, pill: 32, toolbarButton: Size.minTarget, switcherItem: 32, switcherHeight: 32,
            columnWidth: 260, panelWidth: 560, panelRow: 34, panelTopFraction: 0.3, sheetWidth: 380, selectionBar: 0),
        type: TypeScale(
            row: TextRole(.body), rowSelected: TextRole(.body, .semibold),
            sectionHeader: TextRole(.caption, .medium), columnTitle: TextRole(.headline),
            pill: TextRole(.callout), panelField: TextRole(.body), panelTitle: TextRole(.body, .medium),
            panelDetail: TextRole(.body), panelAction: TextRole(.caption, .semibold), banner: TextRole(.callout),
            sheetTitle: TextRole(.headline), sheetBody: TextRole(.callout), switcherLabel: TextRole(.callout, .semibold)),
        materials: Materials(
            column: .none, pill: .layer, switcher: .glass(tint: 0), panel: .glass(tint: 0), banner: .glass(tint: 0),
            selection: .tint),
        frame: FrameStyle(
            light: GradientSpec(top: 0.34, middle: 0.28, bottom: 0.24),
            dark: GradientSpec(top: 0.36, middle: 0.30, bottom: 0.26),
            axis: .vertical, glow: 0))
}

extension EnvironmentValues {
    /// The tokens of the current direction; every kit component reads them from here.
    @Entry public var designTokens: DesignTokens = .quietGlass
    /// The Theme the kit derives its colour roles from.
    @Entry public var designTheme: Theme = Theme(id: "indigo-blue", primary: .indigo, secondary: .blue)
}

extension View {
    /// Sets the direction and Theme for the views below, and tints them with the Theme's primary hue.
    public func design(_ tokens: DesignTokens, theme: Theme) -> some View {
        tint(theme.primary.color)
            .environment(\.designTokens, tokens)
            .environment(\.designTheme, theme)
    }
}
