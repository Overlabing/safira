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
    }

    /// Every surface a row of the column sits on: the bare gradient, the hover, current and selected fills, and the
    /// panel of an open Folder.
    public static let rowSurfaces: [LegibilityCase.SurfaceKind] = [.frame, .hoveredRow, .currentRow, .selectedRow, .layerPanel]

    /// A Tab row's title, in the label colour (semibold when selected).
    public static let tabTitle = Text(name: "Tab title", role: .primaryText, surfaces: rowSurfaces)
    /// A Tab row's subtitle (the host, "Playing"), in the kit's secondary ink.
    public static let tabSubtitle = Text(name: "Tab subtitle", role: .secondaryText, surfaces: rowSurfaces)
    /// The address in the field pill and the Command bar's text, on glass.
    public static let address = Text(name: "Address", role: .primaryText, surfaces: [.glass])
    /// The Private window's band: `ColorRoles.bandText` on `ColorRoles.bandFill`, the Theme's hue, opaque.
    public static let privateBand = Text(name: "Private band", role: .textOnHue, surfaces: [.solidHue])
    /// The Active profile's chooser at the bottom of the column: a field pill, its name in the label colour on glass.
    public static let profilePill = Text(name: "Profile pill", role: .primaryText, surfaces: [.glass])

    /// The selected Tab row's marker, drawn by the kit at its leading edge (`ColorRoles.selectionMarker`, 3:1); under
    /// Increase Contrast the row's outline takes its place.
    public static let selectedTabMarker = Text(name: "Selected Tab marker", role: .selectionMarker, surfaces: [.selectedRow])

    public static let texts = [tabTitle, tabSubtitle, address, privateBand, profilePill, selectedTabMarker]

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

    /// The solver's cases for `text` in `theme` and `appearance`, measured with the kit's tokens.
    public static func cases(of text: Text, for theme: Theme, in appearance: Appearance) -> [LegibilityCase] {
        DesignTokens.standard.legibilityCases(for: theme, in: appearance)
            .filter { $0.role == text.role && text.surfaces.contains($0.surface) }
    }
}
