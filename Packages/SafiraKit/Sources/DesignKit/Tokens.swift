// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SwiftUI
import ThemeStandIn

/// Every layout, shape, emphasis, type and material value a view may use. A view never writes a raw number: a new
/// value becomes a token here first. One instance per visual direction; the chosen one becomes the only one.
public struct DesignTokens: Sendable, Equatable {
    public var name: String
    public var spacing: Spacing
    public var radius: Radius
    public var emphasis: Emphasis
    public var size: Size
    public var type: TypeScale
    public var materials: Materials
    public var frame: FrameStyle
}

extension DesignTokens {
    /// The spacing scale (2, 4, 8, 12, 16, 24) and the semantic picks a direction makes from it.
    public struct Spacing: Sendable, Equatable {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
        public static let scale: [CGFloat] = [xxs, xs, s, m, l, xl]

        /// Horizontal margin of a list column: row content, pills and the switcher align on it.
        public var listMargin: CGFloat
        /// Vertical gap between the fills of two neighbouring rows: they never touch.
        public var rowGap: CGFloat
        /// A row fill's inset around its content.
        public var rowInsetVertical: CGFloat
        public var rowInsetHorizontal: CGFloat
        /// Under a section header, before the first row's fill.
        public var sectionHeaderBottom: CGFloat
        /// Leading tile to the text column of a row.
        public var tileToText: CGFloat
        /// Merge distance of glass shapes inside one `GlassEffectContainer`.
        public var glassMerge: CGFloat
        /// The frame's width around the inset page.
        public var pageInset: CGFloat
        /// Between two groups stacked in a column (toolbar, pill, sections).
        public var groupGap: CGFloat
        /// Inside a floating panel: field insets and the inset of its rows.
        public var panelFieldVertical: CGFloat
        public var panelFieldHorizontal: CGFloat
        public var panelInset: CGFloat
        /// A banner's content inside its shape.
        public var bannerVertical: CGFloat
        public var bannerHorizontal: CGFloat
        /// A sheet's margins.
        public var sheetMargin: CGFloat
    }

    /// Corner radii, always `.continuous`. Nested shapes stay concentric: outer = inner + inset.
    public struct Radius: Sendable, Equatable {
        public var tile: CGFloat
        public var row: CGFloat
        /// Nil draws a capsule.
        public var pill: CGFloat?
        public var page: CGFloat
        /// A floating panel, concentric to its rows.
        public var panel: CGFloat
        /// A surface holding a whole column (a glass sidebar), when the direction draws one.
        public var column: CGFloat
        public var banner: CGFloat?
        public var sheet: CGFloat
    }

    /// Opacities applied to the Theme's tint, or to `.primary` where named.
    public struct Emphasis: Sendable, Equatable {
        public var hover: Double
        /// Hover of a lifted selection style in light, where the lift is white over the frame.
        public var hoverLiftLight: Double
        public var selectedDark: Double
        public var selectedLight: Double
        /// Light hues (orange, teal, mint, cyan, green, yellow) need a stronger light selection to stand off the frame.
        public var selectedLightBrightHue: Double
        /// A tinted glass capsule (the selected switcher item).
        public var glassTint: Double
        /// A recessed fill in `.primary` (a pill drawn without glass, a folder's panel).
        public var layer: Double
        /// A tile's fill behind a glyph with no image.
        public var tileFill: Double
        /// Increase Contrast raises tinted fills by this factor, capped at opaque.
        public var increasedContrastFactor: Double
        /// Veil of window background inside a floating panel's glass, for legibility over any page.
        public var panelVeil: Double
        /// Scrim over the page behind a floating panel or a sheet.
        public var scrim: Double
        /// The page's shadow on the frame.
        public var pageShadow: Double
        /// Theme-coloured glow around a floating panel; 0 draws none.
        public var panelGlow: Double

        public func contrasted(_ opacity: Double, _ contrast: ColorSchemeContrast) -> Double {
            contrast == .increased ? min(1, opacity * increasedContrastFactor) : opacity
        }
    }

    /// Fixed dimensions, in points.
    public struct Size: Sendable, Equatable {
        /// Smallest pointer target of a control.
        public static let minTarget: CGFloat = 28
        /// Outline drawn around glass and selected fills under Increase Contrast or Reduce Transparency.
        public static let contrastStroke: CGFloat = 1
        public static let hairline: CGFloat = 0.5

        public var row: CGFloat
        public var tile: CGFloat
        public var glyph: CGFloat
        public var pill: CGFloat
        public var toolbarButton: CGFloat
        public var switcherItem: CGFloat
        public var switcherHeight: CGFloat
        public var columnWidth: CGFloat
        public var panelWidth: CGFloat
        public var panelRow: CGFloat
        public var panelTopFraction: CGFloat
        public var sheetWidth: CGFloat
        /// Thickness of the selected row's leading bar; 0 draws none.
        public var selectionBar: CGFloat
    }

    /// Roles on the system font: a text style and a weight, never a point size.
    public struct TypeScale: Sendable, Equatable {
        public var row: TextRole
        public var rowSelected: TextRole
        public var sectionHeader: TextRole
        public var columnTitle: TextRole
        public var pill: TextRole
        public var panelField: TextRole
        public var panelTitle: TextRole
        public var panelDetail: TextRole
        public var panelAction: TextRole
        public var banner: TextRole
        public var sheetTitle: TextRole
        public var sheetBody: TextRole
        public var switcherLabel: TextRole
    }

    /// Where glass sits, and what stands in for it.
    public struct Materials: Sendable, Equatable {
        public var column: Surface
        public var pill: Surface
        public var switcher: Surface
        public var panel: Surface
        public var banner: Surface
        public var selection: SelectionStyle
    }

    /// The frame drawn behind everything: the Theme's gradient and how it runs.
    public struct FrameStyle: Sendable, Equatable {
        public var light: GradientSpec
        public var dark: GradientSpec
        public var axis: GradientAxis
        /// A soft glow of the secondary hue in the top trailing corner; 0 draws none.
        public var glow: Double
    }
}

public struct TextRole: Sendable, Equatable {
    public var style: Font.TextStyle
    public var weight: Font.Weight
    public var tracking: CGFloat
    public var uppercased: Bool

    public init(_ style: Font.TextStyle, _ weight: Font.Weight = .regular, tracking: CGFloat = 0, uppercased: Bool = false) {
        self.style = style
        self.weight = weight
        self.tracking = tracking
        self.uppercased = uppercased
    }

    public var font: Font { .system(style, weight: weight) }
}

/// How a surface is drawn. Glass falls back to an opaque fill under Reduce Transparency (`surface(_:in:)`).
public enum Surface: Sendable, Equatable {
    case none
    /// A recessed fill of `.primary` at `Emphasis.layer`.
    case layer
    case glass(tint: Double)
    case clearGlass
}

/// How the selected row reads.
public enum SelectionStyle: Sendable, Equatable {
    /// The Theme's tint at `Emphasis.selected…`.
    case tint
    /// A neutral raised fill (white in dark, white over the frame in light), as lifted paper.
    case lift
}

public enum GradientAxis: Sendable, Equatable {
    case vertical
    case diagonal
}
