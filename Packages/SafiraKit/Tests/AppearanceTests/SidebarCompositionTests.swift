// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import ColorCore
import ColorPlatform
import DesignKit
import Testing

/// Safira's own compositions, checked with ThemeKit's solver on every Theme Safira draws with, in light, dark and both
/// Increase Contrast appearances.
struct SidebarCompositionTests {
    private static let cases: [(theme: Theme, appearance: Appearance)] =
        SidebarComposition.themes.flatMap { theme in Appearance.allCases.map { (theme, $0) } }

    private func expectLegible(_ text: SidebarComposition.Text, _ theme: Theme, _ appearance: Appearance,
                               count: Int) {
        let cases = SidebarComposition.cases(of: text, for: theme, in: appearance)
        #expect(cases.count == count, "\(text.name)")
        for found in cases {
            #expect(found.after >= found.threshold, "\(text.name): \(found)")
        }
    }

    @Test(arguments: SidebarCompositionTests.cases)
    func aTabTitleReachesFourPointFiveOnEveryRowSurface(_ theme: Theme, _ appearance: Appearance) {
        expectLegible(SidebarComposition.tabTitle, theme, appearance, count: 5)
    }

    @Test(arguments: SidebarCompositionTests.cases)
    func aTabSubtitleReachesFourPointFiveOnEveryRowSurface(_ theme: Theme, _ appearance: Appearance) {
        expectLegible(SidebarComposition.tabSubtitle, theme, appearance, count: 5)
    }

    @Test(arguments: SidebarCompositionTests.cases)
    func theAddressReachesFourPointFiveOnGlass(_ theme: Theme, _ appearance: Appearance) {
        expectLegible(SidebarComposition.address, theme, appearance, count: 1)
    }

    @Test(arguments: SidebarCompositionTests.cases)
    func thePrivateBandReachesFourPointFive(_ theme: Theme, _ appearance: Appearance) {
        expectLegible(SidebarComposition.privateBand, theme, appearance, count: 1)
    }

    @Test(arguments: SidebarCompositionTests.cases)
    func theProfilePillReachesFourPointFiveOnGlass(_ theme: Theme, _ appearance: Appearance) {
        expectLegible(SidebarComposition.profilePill, theme, appearance, count: 1)
    }

    /// The worst page behind the Command bar is white in dark and black in light: the field's text, a suggestion's
    /// title and detail, and the highlighted suggestion all stay at 4.5:1.
    @Test(arguments: SidebarCompositionTests.cases)
    func theCommandBarStaysLegibleOverABrightOrADarkPage(_ theme: Theme, _ appearance: Appearance) {
        let colors = ResolvedColors(theme, in: appearance)
        let roles = ColorRoles(theme: theme, tokens: .standard, appearance: appearance)
        let panel = SidebarComposition.commandBarSurfaces(in: appearance, theme: theme)
        let highlighted = panel.map { colors.primary.opacity(roles.selectionOpacity).composited(over: $0) }
        #expect(Contrast.worst(foreground: colors.label, on: panel + highlighted) >= 4.5)
        #expect(Contrast.worst(foreground: roles.secondaryTextRGBA, on: panel + highlighted) >= 4.5)
    }

    @Test(arguments: SidebarCompositionTests.cases)
    func theSelectedTabMarkerReachesThreeOutsideIncreaseContrast(_ theme: Theme, _ appearance: Appearance) {
        let cases = SidebarComposition.cases(of: SidebarComposition.selectedTabMarker, for: theme, in: appearance)
        #expect(cases.count == (appearance.isIncreasedContrast ? 0 : 1))
        for found in cases {
            #expect(found.threshold == 3)
            #expect(found.after >= 3, "\(found)")
        }
    }

    @Test func theTextsAreMeasuredAgainstTheKitsThresholds() {
        let tokens = DesignTokens.standard
        #expect(tokens.emphasis.textContrast == 4.5)
        #expect(SidebarComposition.texts.map(\.name) == ["Tab title", "Tab subtitle", "Address", "Private band", "Profile pill", "Selected Tab marker"])
        #expect(SidebarComposition.themes.count == 8)
        #expect(SidebarComposition.privateTheme.primary == .purple)
    }
}

extension Theme: CustomTestStringConvertible {
    public var testDescription: String { id }
}
