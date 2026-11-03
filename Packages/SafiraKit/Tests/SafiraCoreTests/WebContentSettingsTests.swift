// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import Testing

@Test func aFreshProfileWarnsAboutFraudulentSitesAndBlocksAutoplayingSound() {
    let settings = WebContentSettings()

    #expect(settings.isFraudulentSiteWarningEnabled == true)
    #expect(settings.isAutoplayingSoundAllowed == false)
}

@Test func theRegistryListsBothDefaultsWithTheirValues() {
    let entries = WebContentSettings.defaultEntries

    #expect(entries.map(\.id) == ["web.fraudulentSiteWarning", "web.autoplayingSound"])
    #expect(entries.map(\.title) == ["Warn about fraudulent websites", "Allow autoplaying sound"])
    #expect(entries.map(\.value) == ["On", "Blocked"])
    #expect(entries.map(\.whereToChange) == ["View menu", "View menu"])
}

@Test func theFraudulentSiteWarningSaysItMayConsultAThirdPartyService() throws {
    let entry = try #require(WebContentSettings.defaultEntries.first { $0.id == "web.fraudulentSiteWarning" })

    #expect(entry.explanation.contains("may consult a third-party service"))
}

@Test func settingsSurviveEncodingAndDecoding() throws {
    let settings = WebContentSettings(isFraudulentSiteWarningEnabled: false, isAutoplayingSoundAllowed: true)

    let decoded = try JSONDecoder().decode(WebContentSettings.self, from: JSONEncoder().encode(settings))

    #expect(decoded == settings)
}
