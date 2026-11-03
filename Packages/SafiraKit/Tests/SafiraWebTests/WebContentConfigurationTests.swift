// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraWeb
import Testing
import WebKit

@MainActor
@Suite struct WebContentConfigurationTests {
    @Test func aPageOfADefaultProfileIsInspectableWarnsAboutFraudAndBlocksAutoplayingSound() async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let page = context.makePage(for: TabID())

            #expect(page.webView.isInspectable == true)
            #expect(page.webView.configuration.preferences.isFraudulentWebsiteWarningEnabled == true)
            #expect(page.webView.configuration.mediaTypesRequiringUserActionForPlayback == .audio)

            page.close()
        }
        try await removeDataStoreWhenReleased(profile)
    }

    @Test func changedSettingsReachNewPagesAndLeaveOpenPagesAlone() async throws {
        let profile = ProfileID(rawValue: UUID())
        do {
            let context = ProfileWebContext(profileID: profile)
            let before = context.makePage(for: TabID())

            context.webContentSettings.isFraudulentSiteWarningEnabled = false
            context.webContentSettings.isAutoplayingSoundAllowed = true
            let after = context.makePage(for: TabID())

            #expect(after.webView.configuration.preferences.isFraudulentWebsiteWarningEnabled == false)
            #expect(after.webView.configuration.mediaTypesRequiringUserActionForPlayback == [])
            #expect(after.webView.isInspectable == true)
            #expect(before.webView.configuration.preferences.isFraudulentWebsiteWarningEnabled == true)
            #expect(before.webView.configuration.mediaTypesRequiringUserActionForPlayback == .audio)

            before.close()
            after.close()
        }
        try await removeDataStoreWhenReleased(profile)
    }

    @Test func eachProfileAppliesItsOwnSettings() async throws {
        let strict = ProfileID(rawValue: UUID())
        let loose = ProfileID(rawValue: UUID())
        do {
            let strictPage = ProfileWebContext(profileID: strict).makePage(for: TabID())
            let loosePage = ProfileWebContext(
                profileID: loose,
                webContentSettings: WebContentSettings(isFraudulentSiteWarningEnabled: false, isAutoplayingSoundAllowed: true)
            ).makePage(for: TabID())

            #expect(strictPage.webView.configuration.mediaTypesRequiringUserActionForPlayback == .audio)
            #expect(loosePage.webView.configuration.mediaTypesRequiringUserActionForPlayback == [])
            #expect(loosePage.webView.configuration.preferences.isFraudulentWebsiteWarningEnabled == false)

            strictPage.close()
            loosePage.close()
        }
        try await removeDataStoreWhenReleased(strict)
        try await removeDataStoreWhenReleased(loose)
    }
}
