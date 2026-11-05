// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Observation
import SafiraCore

public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome
    case profile
    case searchEngine
    case shortcuts
    case defaultBrowser
    case defaults
}

/// The onboarding as a sequence of steps. Going back keeps what was entered; nothing is applied until `finish`, and
/// finishing needs a Profile name and a search engine the user chose.
@MainActor
@Observable
public final class OnboardingModel {
    public private(set) var step: OnboardingStep = .welcome
    public var profileName: String
    public var profileSymbol: String
    public var searchEngine: SearchEngine?
    public var shortcutPreset: ShortcutPreset?
    public let defaults: DefaultsSummaryModel
    @ObservationIgnored private let commit: (OnboardingChoices) -> Void

    /// - Parameters:
    ///   - commit: receives all the choices, once, when the user finishes.
    public init(profileName: String, profileSymbol: String, defaults: DefaultsSummaryModel = DefaultsSummaryModel(),
                commit: @escaping (OnboardingChoices) -> Void) {
        self.profileName = profileName
        self.profileSymbol = profileSymbol
        self.defaults = defaults
        self.commit = commit
        refreshDisplayedValues()
    }

    public var choices: OnboardingChoices {
        OnboardingChoices(profileName: profileName, profileSymbol: profileSymbol, searchEngine: searchEngine,
                          shortcutPreset: shortcutPreset, toggles: defaults.toggles)
    }

    public var isFirstStep: Bool { step == .welcome }
    public var isLastStep: Bool { step == .defaults }

    /// The profile step needs a name; the search engine step needs an engine. Every other step may be passed, which
    /// leaves the default and records no acceptance.
    public var canContinue: Bool {
        switch step {
        case .profile: !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .searchEngine: searchEngine != nil
        default: true
        }
    }

    public func next() {
        guard canContinue, let following = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = following
        refreshDisplayedValues()
    }

    public func back() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    /// Hands the choices over, only from the last step and only when they are complete. True when it did.
    @discardableResult
    public func finish() -> Bool {
        let choices = choices
        guard isLastStep, choices.isComplete else { return false }
        commit(choices)
        return true
    }

    private func refreshDisplayedValues() {
        defaults.displayedValues["search.engine"] = searchEngine?.name
            ?? String(localized: "Not chosen", table: "Onboarding", bundle: .module,
                      comment: "Onboarding, defaults step: the value of Search engine before a choice")
        defaults.displayedValues["shortcuts.preset"] = shortcutPreset?.data.name
            ?? String(localized: "Safira's own shortcuts", table: "Onboarding", bundle: .module,
                      comment: "Onboarding, defaults step: the value of Shortcut preset without a preset")
    }
}
