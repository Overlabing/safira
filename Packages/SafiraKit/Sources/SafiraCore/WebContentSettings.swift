// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// How a Profile's web pages behave by default. A change applies to the pages created after it: WebKit reads the
/// configuration once, when it builds a page.
public struct WebContentSettings: Hashable, Sendable, Codable {
    /// WebKit warns before showing a page it considers fraudulent.
    public var isFraudulentSiteWarningEnabled: Bool
    /// Whether a page may start playing sound without a gesture from the user.
    public var isAutoplayingSoundAllowed: Bool

    public init(isFraudulentSiteWarningEnabled: Bool = true, isAutoplayingSoundAllowed: Bool = false) {
        self.isFraudulentSiteWarningEnabled = isFraudulentSiteWarningEnabled
        self.isAutoplayingSoundAllowed = isAutoplayingSoundAllowed
    }

    public static let fraudulentSiteWarningTitle = "Warn about fraudulent websites"
    public static let autoplayingSoundTitle = "Allow autoplaying sound"

    public static let fraudulentSiteWarningExplanation =
        "Before a page loads, WebKit checks the site against a list of known fraudulent sites and warns you if it "
        + "matches. This check may consult a third-party service, which can learn which sites you visit."
    public static let autoplayingSoundExplanation =
        "A page cannot play sound until you click or press a key on it. Silent video can still start by itself."

    /// The entries this type contributes to the registry of defaults, with the values of a fresh `WebContentSettings`.
    public static var defaultEntries: [DefaultEntry] {
        let defaults = WebContentSettings()
        return [
            DefaultEntry(
                id: "web.fraudulentSiteWarning",
                title: fraudulentSiteWarningTitle,
                value: defaults.isFraudulentSiteWarningEnabled ? "On" : "Off",
                explanation: fraudulentSiteWarningExplanation,
                whereToChange: "View menu"
            ),
            DefaultEntry(
                id: "web.autoplayingSound",
                title: autoplayingSoundTitle,
                value: defaults.isAutoplayingSoundAllowed ? "Allowed" : "Blocked",
                explanation: autoplayingSoundExplanation,
                whereToChange: "View menu"
            ),
        ]
    }
}
