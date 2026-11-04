// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Commands
import Onboarding
import SafiraCore
import SafiraWeb
import SwiftUI

/// Connects the registry of defaults to the settings that hold them, for onboarding and for the Defaults window. A
/// switch of the Defaults window changes its setting at once; onboarding hands all of them over when it finishes.
@MainActor
final class DefaultsController: NSObject {
    private let registry: ProfileRegistry
    private let updates: UpdateController
    private let diagnostics: DiagnosticsController
    private let links: LinkController
    private let shortcuts: ShortcutController
    private let sidebarSide: SidebarSideSetting
    private var window: NSWindow?

    init(registry: ProfileRegistry, updates: UpdateController, diagnostics: DiagnosticsController, links: LinkController,
         shortcuts: ShortcutController, sidebarSide: SidebarSideSetting) {
        self.sidebarSide = sidebarSide
        self.registry = registry
        self.updates = updates
        self.diagnostics = diagnostics
        self.links = links
        self.shortcuts = shortcuts
    }

    /// The position of the switch of an entry right now. The web content switches belong to the Active profile.
    func isOn(_ id: String) -> Bool? {
        switch id {
        case "updates.automaticChecks": updates.automaticallyChecks
        case "diagnostics.debugMode": diagnostics.isDebugModeEnabled
        case "web.fraudulentSiteWarning": registry.active.webContentSettings.isFraudulentSiteWarningEnabled
        case "web.autoplayingSound": registry.active.webContentSettings.isAutoplayingSoundAllowed
        case "linkMatching.focusOpenTab": links.focusesMatchingTab
        case "linkPicker.askForSpace": links.asksForSpaceToo
        case "linkPicker.choiceLog": links.logsChoices
        case SidebarSideStore.key: sidebarSide.isRight
        default: nil
        }
    }

    func set(_ id: String, isOn: Bool) {
        switch id {
        case "updates.automaticChecks": updates.automaticallyChecks = isOn
        case "diagnostics.debugMode": diagnostics.setDebugMode(isOn)
        case "web.fraudulentSiteWarning": registry.active.webContentSettings.isFraudulentSiteWarningEnabled = isOn
        case "web.autoplayingSound": registry.active.webContentSettings.isAutoplayingSoundAllowed = isOn
        case "linkMatching.focusOpenTab": links.focusesMatchingTab = isOn
        case "linkPicker.askForSpace": links.asksForSpaceToo = isOn
        case "linkPicker.choiceLog": links.logsChoices = isOn
        case SidebarSideStore.key: sidebarSide.isRight = isOn
        default: break
        }
    }

    /// The model of the Defaults window: switches at their present positions, applied as they move.
    func makeSummaryModel() -> DefaultsSummaryModel {
        let model = DefaultsSummaryModel(current: { [unowned self] in isOn($0) }, apply: { [unowned self] id, isOn in
            set(id, isOn: isOn)
        })
        model.displayedValues["search.engine"] = registry.active.session.settings.searchEngine?.name ?? "Not chosen"
        model.displayedValues["shortcuts.preset"] = shortcuts.configuration.preset?.data.name ?? "Safira's own shortcuts"
        return model
    }

    /// The model onboarding fills in: nothing is applied until it finishes, so the switches start at the documented
    /// defaults whatever the settings hold.
    func makeOnboardingSummary() -> DefaultsSummaryModel {
        DefaultsSummaryModel()
    }

    var defaultBrowserActions: (isDefault: () -> Bool, make: () -> Void) {
        ({ [links] in links.isDefaultBrowser }, { [links] in links.makeDefaultBrowser(nil) })
    }

    // MARK: First launch

    /// Writes every choice of the onboarding at once: the first Profile with its engine and web content settings, the
    /// Shortcut preset and the other switches.
    func commit(_ choices: OnboardingChoices) {
        guard let engine = choices.searchEngine else { return }
        let web = WebContentSettings(
            isFraudulentSiteWarningEnabled: choices.toggles["web.fraudulentSiteWarning"] ?? true,
            isAutoplayingSoundAllowed: choices.toggles["web.autoplayingSound"] ?? false)
        registry.completeOnboarding(name: choices.profileName, symbol: choices.profileSymbol, searchEngine: engine,
                                    webContent: web)
        if let preset = choices.shortcutPreset { shortcuts.choose(preset) }
        for (id, wanted) in choices.toggles where !id.hasPrefix("web.") && wanted != isOn(id) {
            set(id, isOn: wanted)
        }
    }

    // MARK: The Defaults window

    @objc func showDefaults(_ sender: Any?) {
        let view = DefaultsWindowView(model: makeSummaryModel(), controller: self)
        let window = self.window ?? {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 640),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = String(localized: "Defaults")
            window.isReleasedWhenClosed = false
            window.center()
            return window
        }()
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(NSSize(width: 600, height: 640))
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: Choices that are not switches

    var activeProfileName: String { registry.activeProfile.name }

    var searchEngine: SearchEngine? {
        get { registry.active.session.settings.searchEngine }
        set { if let newValue { registry.active.session.chooseSearchEngine(newValue) } }
    }

    var shortcutPreset: ShortcutPreset? {
        get { shortcuts.configuration.preset }
        set { shortcuts.choose(newValue) }
    }
}
