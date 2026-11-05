// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import ColorCore
import ColorPlatform
import DesignKit

/// The text Safira composes from the kit's pieces, described as ThemeKit legibility roles on the surfaces they sit on,
/// so that the solver can check them for every Theme Safira offers. The sidebar draws them with `ListRow` and
/// `ColorRoles` and the kit's `standard` tokens; no Safira number changes a colour.
public enum SidebarComposition {
    public struct Text: Sendable {
        public let name: String
        public let role: LegibilityCase.Role
        public let surfaces: [LegibilityCase.SurfaceKind]
        /// Inside the column's own surface (`ColumnSurface`), or on the window's gradient.
        public var placement: SurfacePlacement = .column
    }

    /// Every surface a row of the column sits on: the column's fill, the hover, current and selected fills, and the
    /// panel of an open Folder.
    public static let rowSurfaces: [LegibilityCase.SurfaceKind] = [.columnFill, .hoveredRow, .currentRow, .selectedRow, .layerPanel]

    /// A Tab row's title, in the label colour (semibold when selected).
    public static let tabTitle = Text(name: "Tab title", role: .primaryText, surfaces: rowSurfaces)
    /// A Tab row's subtitle (the host, "Playing"), in the kit's secondary ink.
    public static let tabSubtitle = Text(name: "Tab subtitle", role: .secondaryText, surfaces: rowSurfaces)
    /// The address in the field pill and the Command bar's text, on glass.
    public static let address = Text(name: "Address", role: .primaryText, surfaces: [.glass])
    /// The Private window's band: `ColorRoles.bandText` on `ColorRoles.bandFill`, the Theme's hue, opaque. Text on the
    /// opaque hue is measured with the frame's cases.
    public static let privateBand = Text(name: "Private band", role: .textOnHue, surfaces: [.solidHue], placement: .frame)
    /// The Space rail's caption above the row: the hovered or focused item's name in the label colour, on the column's
    /// fill.
    public static let railCaption = Text(name: "Space rail caption", role: .primaryText, surfaces: [.columnFill])
    /// The caption's detail and shortcut ("3 Spaces · opens Home", "⌃2"), in the kit's secondary ink.
    public static let railCaptionDetail = Text(name: "Space rail caption detail", role: .secondaryText,
                                               surfaces: [.columnFill])
    /// The column's edge, against the gradient beside it and against its own fill.
    public static let columnEdge = Text(name: "Column edge", role: .columnEdge, surfaces: [.frame, .columnFill])

    /// The selected Tab row's marker, drawn by the kit at its leading edge (`ColorRoles.selectionMarker`, 3:1); under
    /// Increase Contrast the row's outline takes its place.
    public static let selectedTabMarker = Text(name: "Selected Tab marker", role: .selectionMarker, surfaces: [.selectedRow])

    public static let texts = [tabTitle, tabSubtitle, address, privateBand, railCaption, railCaptionDetail, selectedTabMarker,
                               columnEdge]

    /// The floating Command bar sits over any page, so its glass stands on a veil of the window background this opaque:
    /// whatever the page behind it, white or black, its text and rows read as on the plain window.
    public static let commandBarVeil = 0.9

    /// What the Command bar's text sits on, at worst: the veil over a white page and over a black one, glass ignored
    /// (it only moves the result toward the veil).
    public static func commandBarSurfaces(in appearance: Appearance, theme: Theme) -> [RGBA] {
        let background = ResolvedColors(theme, in: appearance).background
        return [RGBA.white, RGBA.black].map { background.opacity(commandBarVeil).composited(over: $0) }
    }

    /// A Private window wears this Theme, always in the dark appearance: the purple that tells it from the Main window.
    public static let privateTheme = Theme(id: "private", primary: .purple, secondary: .indigo)

    /// The Themes Safira draws with: the Palette, and the Private window's.
    public static var themes: [Theme] { ThemeCatalog.palette.themes + [privateTheme] }

    /// The Space rail's marks at the bottom of the Main window's column: a quiet glyph on the fill and on its hover disc
    /// (4.5:1), the selected Space's marker, a folded Profile's dots with every system hue counted, and the hairline
    /// before them (3:1). A Private window has no rail.
    public static func railCases(for theme: Theme, in appearance: Appearance) -> [LegibilityCase] {
        DesignTokens.standard.railCases(for: theme, in: appearance)
    }

    /// The solver's cases for `text` in `theme` and `appearance`, measured with the kit's tokens.
    public static func cases(of text: Text, for theme: Theme, in appearance: Appearance) -> [LegibilityCase] {
        DesignTokens.standard.legibilityCases(for: theme, in: appearance, placement: text.placement)
            .filter { $0.role == text.role && text.surfaces.contains($0.surface) }
    }
}
