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

    public static let fraudulentSiteWarningTitle = String(localized: "Warn about fraudulent websites", table: "SafiraCore",
                                                          bundle: .module, comment: "Menu item and Defaults title")
    public static let autoplayingSoundTitle = String(localized: "Allow autoplaying sound", table: "SafiraCore",
                                                     bundle: .module, comment: "Menu item and Defaults title")

    public static let fraudulentSiteWarningExplanation = String(localized: """
        Before a page loads, WebKit checks the site against a list of known fraudulent sites and warns you if it \
        matches. This check may consult a third-party service, which can learn which sites you visit.
        """, table: "SafiraCore", bundle: .module, comment: "Defaults: explanation of the fraudulent website warning")
    public static let autoplayingSoundExplanation = String(localized: """
        A page cannot play sound until you click or press a key on it. Silent video can still start by itself.
        """, table: "SafiraCore", bundle: .module, comment: "Defaults: explanation of autoplaying sound")

    /// The entries this type contributes to the registry of defaults, with the values of a fresh `WebContentSettings`.
    public static var defaultEntries: [DefaultEntry] {
        let defaults = WebContentSettings()
        return [
            DefaultEntry(
                id: "web.fraudulentSiteWarning",
                title: fraudulentSiteWarningTitle,
                value: DefaultWording.onOff(defaults.isFraudulentSiteWarningEnabled),
                explanation: fraudulentSiteWarningExplanation,
                whereToChange: DefaultWording.viewMenu,
                control: .toggle(isOn: defaults.isFraudulentSiteWarningEnabled)
            ),
            DefaultEntry(
                id: "web.autoplayingSound",
                title: autoplayingSoundTitle,
                value: defaults.isAutoplayingSoundAllowed
                    ? String(localized: "Allowed", table: "SafiraCore", bundle: .module, comment: "Defaults: value of autoplaying sound")
                    : String(localized: "Blocked", table: "SafiraCore", bundle: .module, comment: "Defaults: value of autoplaying sound"),
                explanation: autoplayingSoundExplanation,
                whereToChange: DefaultWording.viewMenu,
                control: .toggle(isOn: defaults.isAutoplayingSoundAllowed)
            ),
        ]
    }
}
