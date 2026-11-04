// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SwiftUI
import ThemeStandIn

extension View {
    /// Draws `surface` behind the view in `shape`. Glass becomes an opaque window-background fill under Reduce
    /// Transparency; Increase Contrast adds a `.secondary` outline so the shape holds on any background.
    public func surface(_ surface: Surface, in shape: some InsettableShape) -> some View {
        modifier(SurfaceModifier(surface: surface, shape: shape))
    }

    /// Simulates accessibility settings for renders and previews, without touching the Mac's own settings.
    public func accessibilityOverrides(
        increaseContrast: Bool = false, reduceTransparency: Bool = false, reduceMotion: Bool = false
    ) -> some View {
        transformEnvironment(\._colorSchemeContrast) { if increaseContrast { $0 = .increased } }
            .transformEnvironment(\._accessibilityReduceTransparency) { if reduceTransparency { $0 = true } }
            .transformEnvironment(\._accessibilityReduceMotion) { if reduceMotion { $0 = true } }
    }
}

private struct SurfaceModifier<S: InsettableShape>: ViewModifier {
    let surface: Surface
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.designTokens) private var tokens
    @Environment(\.designTheme) private var theme

    func body(content: Content) -> some View {
        switch surface {
        case .none:
            content
        case .layer:
            content
                .background { shape.fill(Color.primary.opacity(tokens.emphasis.contrasted(tokens.emphasis.layer, contrast))) }
                .overlay { outline }
        case .glass, .clearGlass:
            if reduceTransparency {
                content
                    .background {
                        shape.fill(.background)
                            .overlay { if let tint { shape.fill(tint) } }
                    }
                    .overlay { outline }
            } else {
                // The outline is part of the glass's content: drawn after the glass, a container composites it under.
                content
                    .overlay { outline }
                    .glassEffect(glass, in: shape)
            }
        }
    }

    private var tint: Color? {
        if case .glass(let opacity) = surface, opacity > 0 { return theme.primary.color.opacity(opacity) }
        return nil
    }

    private var glass: Glass {
        switch surface {
        case .clearGlass: .clear
        default: tint.map { Glass.regular.tint($0) } ?? .regular
        }
    }

    @ViewBuilder private var outline: some View {
        if contrast == .increased {
            shape.strokeBorder(.secondary, lineWidth: DesignTokens.Size.contrastStroke).accessibilityHidden(true)
        } else if reduceTransparency {
            shape.strokeBorder(.separator, lineWidth: DesignTokens.Size.contrastStroke).accessibilityHidden(true)
        }
    }
}

/// The capsule or rounded rectangle a token radius asks for; nil radius is a capsule.
public struct TokenShape: InsettableShape {
    let radius: CGFloat?
    var inset: CGFloat = 0

    public init(radius: CGFloat?) {
        self.radius = radius
    }

    public func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: inset, dy: inset)
        if let radius {
            return RoundedRectangle(cornerRadius: max(0, radius - inset), style: .continuous).path(in: rect)
        }
        return Capsule(style: .continuous).path(in: rect)
    }

    public func inset(by amount: CGFloat) -> TokenShape {
        var shape = self
        shape.inset += amount
        return shape
    }
}
