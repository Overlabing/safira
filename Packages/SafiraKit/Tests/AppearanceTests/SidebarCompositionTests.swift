// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import ColorCore
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
    func theProfileBandReachesFourPointFive(_ theme: Theme, _ appearance: Appearance) {
        expectLegible(SidebarComposition.profileBand, theme, appearance, count: 1)
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
        #expect(SidebarComposition.texts.map(\.name) == ["Tab title", "Tab subtitle", "Address", "Profile band", "Selected Tab marker"])
        #expect(SidebarComposition.themes.count == 8)
        #expect(SidebarComposition.privateTheme.primary == .purple)
    }
}

extension Theme: CustomTestStringConvertible {
    public var testDescription: String { id }
}
