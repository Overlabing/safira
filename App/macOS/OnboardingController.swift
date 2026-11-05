// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Onboarding
import SafiraCore
import SafiraWeb
import SwiftUI

/// Shows the onboarding as a sheet over the Main window on the launch that created the first Profile, and again on the
/// next launch if it was not finished. An existing user never gets it.
@MainActor
final class OnboardingController {
    private let registry: ProfileRegistry
    private let defaults: DefaultsController
    private var sheet: NSWindow?

    init(registry: ProfileRegistry, defaults: DefaultsController) {
        self.registry = registry
        self.defaults = defaults
    }

    var isPending: Bool { registry.isOnboardingPending }

    func present(over window: NSWindow, whenFinished: @escaping () -> Void) {
        guard isPending, sheet == nil else { return }
        let profile = registry.activeProfile
        let model = OnboardingModel(profileName: profile.name, profileSymbol: profile.symbol,
                                    defaults: defaults.makeOnboardingSummary()) { [weak self, weak window] choices in
            guard let self else { return }
            defaults.commit(choices)
            if let sheet { window?.endSheet(sheet) }
            sheet = nil
            whenFinished()
        }
        let actions = defaults.defaultBrowserActions
        let view = OnboardingView(model: model, isDefaultBrowser: actions.isDefault, makeDefaultBrowser: actions.make)
        let sheet = NSWindow.sheet(view)
        sheet.title = String(localized: "Welcome to Safira", comment: "Onboarding sheet title")
        self.sheet = sheet
        window.beginSheet(sheet)
    }
}
