// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DesignKit
import SwiftUI
import Testing
import ThemeStandIn

@Suite struct DesignTokensTests {
    @Test(arguments: DesignTokens.all)
    func semanticSpacingComesFromTheScale(_ tokens: DesignTokens) {
        let spacing = tokens.spacing
        for value in [spacing.listMargin, spacing.rowGap, spacing.rowInsetHorizontal, spacing.pageInset, spacing.groupGap] {
            #expect(DesignTokens.Spacing.scale.contains(value))
        }
    }

    @Test(arguments: DesignTokens.all)
    func rowFillsNeverTouchAndStayInsideTheMargin(_ tokens: DesignTokens) {
        #expect(tokens.spacing.rowGap > 0)
        #expect(tokens.spacing.rowInsetHorizontal <= tokens.spacing.listMargin)
    }

    @Test(arguments: DesignTokens.all)
    func everyControlMeetsTheMinimumPointerTarget(_ tokens: DesignTokens) {
        #expect(tokens.size.toolbarButton >= DesignTokens.Size.minTarget)
        #expect(tokens.size.row >= DesignTokens.Size.minTarget)
        #expect(tokens.size.switcherHeight >= DesignTokens.Size.minTarget)
    }

    @Test func theDirectionsHaveDistinctNames() {
        #expect(DesignTokens.all.map(\.name) == ["Quiet Glass", "Deep Glass", "Slim Frame"])
    }
}

@Suite struct ColorRolesTests {
    let indigo = Theme(id: "indigo-blue", primary: .indigo, secondary: .blue)
    let teal = Theme(id: "teal-green", primary: .teal, secondary: .green)

    @Test func increaseContrastRaisesTheSelectionCappedAtOpaque() {
        let normal = ColorRoles(theme: indigo, tokens: .quietGlass, isDark: true, contrast: .standard)
        let raised = ColorRoles(theme: indigo, tokens: .quietGlass, isDark: true, contrast: .increased)
        #expect(normal.selectedOpacity == 0.25)
        #expect(raised.selectedOpacity == 0.45)
        #expect(DesignTokens.slimFrame.emphasis.contrasted(0.7, .increased) == 1)
    }

    @Test func brightHuesGetAStrongerLightSelection() {
        #expect(ColorRoles(theme: indigo, tokens: .quietGlass, isDark: false, contrast: .standard).selectedOpacity == 0.30)
        #expect(ColorRoles(theme: teal, tokens: .quietGlass, isDark: false, contrast: .standard).selectedOpacity == 0.48)
    }

    @Test func theFrameReadsTheAppearancesGradient() {
        #expect(ColorRoles(theme: indigo, tokens: .quietGlass, isDark: true, contrast: .standard).frameSpec == .dark)
        #expect(ColorRoles(theme: indigo, tokens: .quietGlass, isDark: false, contrast: .standard).frameSpec == .light)
    }
}

@Suite struct MotionTests {
    @Test func reduceMotionTurnsMovementIntoTheSharedFadeOrNothing() {
        #expect(MotionRole.panelAppear.resolved(reduceMotion: true) == MotionRole.reducedFade)
        #expect(MotionRole.hoverFill.resolved(reduceMotion: true) == nil)
        #expect(MotionRole.panelAppear.resolved(reduceMotion: false)?.duration == .calm)
    }

    @Test func springsNeverBounceVisibly() {
        for curve in MotionCurve.allCases {
            #expect((curve.bounce ?? 0) <= 0.15)
        }
    }

    @Test func theDurationScale() {
        #expect(MotionDuration.allCases.map(\.rawValue) == [0.12, 0.2, 0.35, 0.5])
    }
}
