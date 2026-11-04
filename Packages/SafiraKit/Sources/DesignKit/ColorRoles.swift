// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SwiftUI
import ThemeStandIn

/// The colours a view may use, derived from a Theme, the tokens and the appearance. Views ask for a role, never for a
/// hue and an opacity of their own.
public struct ColorRoles: Sendable {
    public let theme: Theme
    public let tokens: DesignTokens
    public let isDark: Bool
    public let contrast: ColorSchemeContrast

    public init(theme: Theme, tokens: DesignTokens, isDark: Bool, contrast: ColorSchemeContrast) {
        self.theme = theme
        self.tokens = tokens
        self.isDark = isDark
        self.contrast = contrast
    }

    static let brightHues: Set<Hue> = [.orange, .teal, .mint, .cyan, .green, .yellow]

    public var tint: Color { theme.primary.color }

    /// The frame's gradient opacities for this appearance.
    public var frameSpec: GradientSpec { isDark ? tokens.frame.dark : tokens.frame.light }

    public var frameStops: [Gradient.Stop] {
        let spec = frameSpec
        return [
            .init(color: theme.primary.color.opacity(spec.top), location: 0),
            .init(color: theme.secondary.color.opacity(spec.middle), location: 0.5),
            .init(color: theme.primary.color.opacity(spec.bottom), location: 1),
        ]
    }

    /// Opacity of the selected row's fill (tint style), raised under Increase Contrast.
    public var selectedOpacity: Double {
        let emphasis = tokens.emphasis
        let base: Double
        if isDark {
            base = emphasis.selectedDark
        } else {
            base = Self.brightHues.contains(theme.primary) ? emphasis.selectedLightBrightHue : emphasis.selectedLight
        }
        return emphasis.contrasted(base, contrast)
    }

    public var hoverOpacity: Double { tokens.emphasis.contrasted(tokens.emphasis.hover, contrast) }

    public var selectionFill: Color {
        switch tokens.materials.selection {
        case .tint: tint.opacity(selectedOpacity)
        case .lift: Color.white.opacity(selectedOpacity)
        }
    }

    public var hoverFill: Color {
        switch tokens.materials.selection {
        case .tint: tint.opacity(hoverOpacity)
        case .lift: isDark ? Color.white.opacity(hoverOpacity) : Color.white.opacity(tokens.emphasis.hoverLiftLight)
        }
    }

    public var layerFill: Color { Color.primary.opacity(tokens.emphasis.contrasted(tokens.emphasis.layer, contrast)) }

    public var glassTint: Color { tint.opacity(tokens.emphasis.glassTint) }

    public func glassTint(_ opacity: Double) -> Color? { opacity > 0 ? tint.opacity(opacity) : nil }

    public var tileFill: Color { tint.opacity(tokens.emphasis.tileFill) }
}

extension View {
    /// Reads the colour roles of the current Theme, tokens and appearance.
    public func withColorRoles<V: View>(@ViewBuilder _ content: @escaping (ColorRoles) -> V) -> some View {
        ColorRolesReader(content: content)
    }
}

/// Builds the colour roles from the environment and hands them to its content.
public struct ColorRolesReader<Content: View>: View {
    @Environment(\.designTokens) private var tokens
    @Environment(\.designTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    let content: (ColorRoles) -> Content

    public init(@ViewBuilder content: @escaping (ColorRoles) -> Content) {
        self.content = content
    }

    public var body: some View {
        content(ColorRoles(theme: theme, tokens: tokens, isDark: scheme == .dark, contrast: contrast))
    }
}
