// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import ColorCore
import ColorPlatform
import ColorUI
import SafiraCore
import SwiftUI

// The one place where the Active profile's tint and the Space's Theme reach the sidebar. The design system (#68, #69)
// replaces `sidebarAppearance(profile:space:)` and `ProfileBand`; the data behind them (Profile and Space palette ids,
// legibility in the Appearance module) stays.

extension EnvironmentValues {
    /// The colour of secondary text in the sidebar, solved by ThemeKit so that it stays at 4.5:1 on the Theme's gradient.
    @Entry var sidebarSecondary: Color = .secondary
}

extension View {
    /// Draws the Space's Theme as the sidebar's gradient and tints the sidebar with the Profile's primary hue.
    func sidebarAppearance(profile: Theme, space: Theme) -> some View {
        modifier(SidebarAppearance(profile: profile, space: space))
    }
}

private struct SidebarAppearance: ViewModifier {
    let profile: Theme
    let space: Theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var appearance: ColorCore.Appearance {
        .init(isDark: scheme == .dark, isIncreasedContrast: contrast == .increased)
    }

    func body(content: Content) -> some View {
        let legibility = SidebarSurfaces.legibility(of: space, in: appearance)
        let label = RGBA(.labelColor, in: appearance)
        let secondary = label.opacity(legibility.secondaryAlpha / max(label.alpha, 0.001))
        content
            .scrollContentBackground(.hidden)
            .background {
                GradientBackground(
                    theme: space,
                    light: SidebarSurfaces.gradient(in: contrast == .increased ? .lightIncreasedContrast : .light),
                    dark: SidebarSurfaces.gradient(in: contrast == .increased ? .darkIncreasedContrast : .dark))
                    .ignoresSafeArea()
            }
            .tint(profile.primary.color)
            .environment(\.theme, space)
            .environment(\.sidebarSecondary,
                         Color(.sRGB, red: secondary.red, green: secondary.green, blue: secondary.blue,
                               opacity: secondary.alpha))
    }
}

/// The flat band of the Profile's primary hue under the Profile switcher: what tells the Active profile at a glance.
struct ProfileBand: ViewModifier {
    let theme: Theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let appearance = ColorCore.Appearance(isDark: scheme == .dark, isIncreasedContrast: contrast == .increased)
        let band = SidebarSurfaces.profileBandColor(of: theme, in: appearance)
        let ink = SidebarSurfaces.profileBandInk(of: theme, in: appearance)
        let inkColor = Color(.sRGB, red: ink.red, green: ink.green, blue: ink.blue)
        content
            .foregroundStyle(inkColor)
            .background(Color(.sRGB, red: band.red, green: band.green, blue: band.blue))
    }
}

/// The Palette's Themes as swatches, one selected: the picker of the Profile and Space editors.
struct PalettePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 10) {
            ForEach(ThemeCatalog.palette.themes) { theme in
                Button {
                    selection = theme.id
                } label: {
                    ThemeSwatch(theme, isSelected: selection == theme.id)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme")
    }
}
