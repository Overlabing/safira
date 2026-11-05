// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Onboarding
import Preferences
import SafiraCore
import Testing

@MainActor
@Suite struct OnboardingModelTests {
    private func model(committed: @escaping (OnboardingChoices) -> Void = { _ in }) -> OnboardingModel {
        OnboardingModel(profileName: "Default", profileSymbol: "👤", commit: committed)
    }

    private func advance(_ model: OnboardingModel, to step: OnboardingStep) {
        while model.step != step { model.next() }
    }

    @Test func noSearchEngineAndNoShortcutPresetIsPreselected() {
        let model = model()

        #expect(model.searchEngine == nil)
        #expect(model.shortcutPreset == nil)
        #expect(model.choices.searchEngine == nil)
    }

    @Test func thePageThatChoosesTheSearchEngineCannotBeLeftWithoutOne() {
        let model = model()
        advance(model, to: .searchEngine)

        model.next()
        #expect(model.step == .searchEngine)
        #expect(model.canContinue == false)

        model.searchEngine = .kagi
        model.next()
        #expect(model.step == .shortcuts)
    }

    @Test func theProfileNeedsANameButABlankOneIsNotAName() {
        let model = model()
        advance(model, to: .profile)

        model.profileName = "   "
        model.next()
        #expect(model.step == .profile)

        model.profileName = "Work"
        model.next()
        #expect(model.step == .searchEngine)
    }

    @Test func theShortcutPresetAndTheDefaultBrowserMayBePassedWithoutAChoice() {
        let model = model()
        model.searchEngine = .duckDuckGo
        advance(model, to: .shortcuts)

        model.next()
        model.next()

        #expect(model.step == .defaults)
        #expect(model.choices.shortcutPreset == nil)
    }

    @Test func goingBackKeepsWhatWasEntered() {
        let model = model()
        model.searchEngine = .ecosia
        advance(model, to: .shortcuts)
        model.shortcutPreset = .arc

        model.back()

        #expect(model.step == .searchEngine)
        #expect(model.searchEngine == .ecosia)
        #expect(model.shortcutPreset == .arc)
    }

    @Test func onboardingShowsEveryUserFacingDefaultOfTheRegistry() {
        let model = model()

        #expect(model.defaults.entries.map(\.id) == DefaultsRegistry.entries.userFacing.map(\.id))
        #expect(model.defaults.entries.allSatisfy { $0.isUserFacing })
    }

    @Test func eachSwitchStartsAtItsDocumentedPositionAndCanBeChanged() {
        let model = model()
        let switches = DefaultsRegistry.entries.userFacing.filter { if case .toggle = $0.control { true } else { false } }

        #expect(model.defaults.toggles == [
            "updates.automaticChecks": false, "diagnostics.debugMode": false, "web.fraudulentSiteWarning": true,
            "web.autoplayingSound": false, "linkMatching.focusOpenTab": true, "linkPicker.askForSpace": false,
            "linkPicker.choiceLog": false, "window.sidebarSide": false,
        ])
        #expect(Set(model.defaults.toggles.keys) == Set(switches.map(\.id)))

        model.defaults.setOn(true, for: "linkPicker.choiceLog")
        model.defaults.setOn(false, for: "web.fraudulentSiteWarning")

        #expect(model.choices.toggles["linkPicker.choiceLog"] == true)
        #expect(model.choices.toggles["web.fraudulentSiteWarning"] == false)
    }

    @Test func finishingHandsOverEveryChoiceOnceFromTheLastStepOnly() {
        var received: [OnboardingChoices] = []
        let model = model { received.append($0) }
        model.profileName = "Work"
        model.profileSymbol = "💼"
        model.searchEngine = .braveSearch
        advance(model, to: .shortcuts)
        model.shortcutPreset = .zen
        model.defaults.setOn(true, for: "updates.automaticChecks")

        #expect(model.finish() == false)
        advance(model, to: .defaults)
        #expect(model.finish())

        #expect(received.count == 1)
        #expect(received.first?.profileName == "Work")
        #expect(received.first?.profileSymbol == "💼")
        #expect(received.first?.searchEngine == .braveSearch)
        #expect(received.first?.shortcutPreset == .zen)
        #expect(received.first?.toggles["updates.automaticChecks"] == true)
    }

    @Test func finishingWithoutASearchEngineHandsNothingOver() {
        var received = 0
        let model = model { _ in received += 1 }
        advance(model, to: .searchEngine)
        model.searchEngine = .google
        advance(model, to: .defaults)
        model.searchEngine = nil

        #expect(model.finish() == false)
        #expect(received == 0)
    }

    @Test func theSummaryNamesTheChosenEngineAndPresetAndSaysWhenNothingWasChosen() {
        let model = model()
        advance(model, to: .searchEngine)
        #expect(model.defaults.displayedValues["search.engine"] == "Not chosen")

        model.searchEngine = .kagi
        model.next()
        model.shortcutPreset = .safari
        advance(model, to: .defaults)

        #expect(model.defaults.displayedValues["search.engine"] == "Kagi")
        #expect(model.defaults.displayedValues["shortcuts.preset"] == "Safari")
    }
}

@MainActor
@Suite struct DefaultsSummaryModelTests {
    @Test func aChangeIsAppliedAtOnceInTheDefaultsWindowAndIgnoredForAnUnknownSwitch() {
        var applied: [String] = []
        let model = DefaultsSummaryModel(current: { $0 == "linkPicker.askForSpace" ? true : nil },
                                         apply: { applied.append("\($0)=\($1)") })

        #expect(model.isOn("linkPicker.askForSpace"))
        model.setOn(false, for: "linkPicker.askForSpace")
        model.setOn(false, for: "linkPicker.askForSpace")
        model.setOn(true, for: "web.httpsFirst")

        #expect(applied == ["linkPicker.askForSpace=false"])
        #expect(model.isOn("web.httpsFirst") == false)
    }
}
