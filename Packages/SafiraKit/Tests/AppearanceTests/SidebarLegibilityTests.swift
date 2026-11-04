// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import ColorCore
import ColorPlatform
import Testing

/// The sidebar's text roles on every Theme of the Palette in light, dark and Increase Contrast, solved by ThemeKit.
struct SidebarLegibilityTests {
    private static let cases: [(theme: Theme, appearance: Appearance)] =
        ThemeCatalog.palette.themes.flatMap { theme in Appearance.allCases.map { (theme, $0) } }

    @Test(arguments: SidebarLegibilityTests.cases)
    func theLabelReachesFourPointFive(_ theme: Theme, _ appearance: Appearance) {
        #expect(SidebarSurfaces.legibility(of: theme, in: appearance).worstLabel >= Contrast.text)
    }

    @Test(arguments: SidebarLegibilityTests.cases)
    func theSecondaryLabelReachesFourPointFive(_ theme: Theme, _ appearance: Appearance) {
        #expect(SidebarSurfaces.legibility(of: theme, in: appearance).worstSecondary >= Contrast.text)
    }

    @Test(arguments: SidebarLegibilityTests.cases)
    func aTextTintedWithThePrimaryHueReachesFourPointFive(_ theme: Theme, _ appearance: Appearance) {
        #expect(SidebarSurfaces.legibility(of: theme, in: appearance).worstTint >= Contrast.text)
    }

    @Test(arguments: SidebarLegibilityTests.cases)
    func theSelectedRowStandsOutFromTheGradient(_ theme: Theme, _ appearance: Appearance) {
        #expect(SidebarSurfaces.legibility(of: theme, in: appearance).selectionShows >= 1.15)
    }

    @Test(arguments: SidebarLegibilityTests.cases)
    func theGradientStillShowsOnTheWindow(_ theme: Theme, _ appearance: Appearance) {
        #expect(SidebarSurfaces.legibility(of: theme, in: appearance).gradientShows >= 1.1)
    }

    @Test(arguments: SidebarLegibilityTests.cases)
    func theProfileBandKeepsItsInkAtFourPointFive(_ theme: Theme, _ appearance: Appearance) {
        #expect(SidebarSurfaces.profileBandContrast(of: theme, in: appearance) >= Contrast.text)
    }

    @Test func theSidebarGradientIsThemeKitsInLightAndThinnerInDark() {
        #expect(SidebarSurfaces.gradient(in: .light) == GradientSpec(top: 0.38, middle: 0.16, bottom: 0.05))
        #expect(SidebarSurfaces.gradient(in: .dark) == GradientSpec(top: 0.30, middle: 0.13, bottom: 0.04))
    }

    @Test func increaseContrastThinsTheGradientByAQuarter() {
        let thinned = SidebarSurfaces.gradient(in: .lightIncreasedContrast)
        #expect(abs(thinned.top - 0.285) < 1e-9)
        #expect(abs(thinned.middle - 0.12) < 1e-9)
        #expect(abs(thinned.bottom - 0.0375) < 1e-9)
    }

    @Test func theWashesAreThinnerInDark() {
        #expect(SidebarSurfaces.surfaces(in: .light).fills == [0.08, 0.12])
        #expect(SidebarSurfaces.surfaces(in: .dark).fills == [0.06, 0.10])
        #expect(SidebarSurfaces.surfaces(in: .light).selection.floor == 0.22)
        #expect(SidebarSurfaces.surfaces(in: .dark).selection.floor == 0.18)
    }

    /// A Profile is more distinct than a Space: its band is opaque, the Space gradient's strongest stop is not.
    @Test func theProfileBandIsOpaqueWhileNoSpaceGradientStopIs() throws {
        for appearance in Appearance.allCases {
            for theme in ThemeCatalog.palette.themes {
                #expect(SidebarSurfaces.profileBandColor(of: theme, in: appearance).alpha == 1)
            }
            #expect(SidebarSurfaces.gradient(in: appearance).top <= 0.38)
        }
    }

    @Test func theBandInkIsWhiteOnIndigoAndBlackOnMintInLight() throws {
        let indigo = try #require(ThemeCatalog.theme(id: "indigo-blue"))
        let mint = try #require(ThemeCatalog.theme(id: "mint-cyan"))
        #expect(SidebarSurfaces.profileBandInk(of: indigo, in: .light) == .white)
        #expect(SidebarSurfaces.profileBandInk(of: mint, in: .light) == .black)
    }
}

extension Theme: CustomTestStringConvertible {
    public var testDescription: String { id }
}
