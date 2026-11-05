// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Preferences
import SafiraCore
import Testing

@MainActor
private func decide(_ link: IncomingLink, profiles: [Profile] = [workProfile, homeProfile], router: LinkRouter? = nil,
                    destination: RecordingDestination) -> LinkDecision {
    (router ?? makeRouter()).decide(for: link, among: profiles, spacesOf: { defaultSpaces[$0] ?? [] },
                                    matchingTab: { destination.matchingTab(for: $1, in: $0) })
}

@MainActor
@Suite struct MatchingTabRoutingTests {
    @Test func aSingleProfileFocusesTheTabThatShowsTheLink() {
        let destination = RecordingDestination(profiles: [workProfile])
        let match = destination.showTab("https://example.com/a/path?q=secret", in: workProfile, space: docsSpace)

        #expect(decide(exampleLink, profiles: [workProfile], destination: destination) == .focus(match))
    }

    @Test func aRuleFocusesTheTabOfItsProfileInAnySpaceEvenWhenTheRuleNamesAnother() {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let match = destination.showTab("https://example.com/a/path?q=secret", in: workProfile, space: docsSpace)
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work", space: "Dev")]))

        #expect(decide(exampleLink, router: router, destination: destination) == .focus(match))
    }

    @Test func aRuleThatForcesANewTabSkipsMatchingAltogether() {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        destination.showTab("https://example.com/a/path?q=secret", in: workProfile, space: devSpace)
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work", forcesNewTab: true)]))

        #expect(decide(exampleLink, router: router, destination: destination)
            == .open(LinkTarget(profile: workProfile.id, forcesNewTab: true)))
        #expect(destination.lookups == 0)
    }

    @Test func withTheSettingOffEveryLinkOpensANewTab() {
        let destination = RecordingDestination(profiles: [workProfile])
        destination.showTab("https://example.com/a/path?q=secret", in: workProfile, space: devSpace)

        #expect(decide(exampleLink, profiles: [workProfile], router: makeRouter(matching: false), destination: destination)
            == .open(LinkTarget(profile: workProfile.id)))
        #expect(destination.lookups == 0)
    }

    @Test func onlyTheTargetProfileIsSearched() {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        destination.showTab("https://example.com/a/path?q=secret", in: homeProfile, space: readingSpace)
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work")]))

        #expect(decide(exampleLink, router: router, destination: destination) == .open(LinkTarget(profile: workProfile.id)))
    }

    @Test func withSeveralProfilesAndNoRuleTheUserStillChooses() {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        destination.showTab("https://example.com/a/path?q=secret", in: homeProfile, space: readingSpace)

        #expect(decide(exampleLink, destination: destination) == .ask)
    }

    @Test func aLinkThatIsNotAWebAddressIsNeverMatched() {
        let destination = RecordingDestination(profiles: [workProfile])
        let file = IncomingLink(url: URL(fileURLWithPath: "/tmp/page.html"))

        #expect(decide(file, profiles: [workProfile], destination: destination) == .open(LinkTarget(profile: workProfile.id)))
        #expect(destination.lookups == 0)
    }

    @Test func anInstalledNativeAppStillComesFirst() {
        let destination = RecordingDestination(profiles: [workProfile])
        destination.showTab("https://www.figma.com/design/AbC/Landing", in: workProfile, space: devSpace)
        let router = makeRouter(applications: StubApplications(installed: [.figma]))

        let decision = decide(link("https://www.figma.com/design/AbC/Landing"), profiles: [workProfile], router: router,
                              destination: destination)

        guard case .openNative = decision else {
            Issue.record("expected the native app to decide, got \(decision)")
            return
        }
    }

    // MARK: Coordinator

    @Test func theSameLinkDeliveredTwiceFocusesTheTabTheFirstOneOpened() async {
        let destination = RecordingDestination(profiles: [workProfile])
        let coordinator = makeCoordinator(destination, ScriptedChooser())

        coordinator.receive(link("https://example.com/a/path?q=secret"))
        await coordinator.waitUntilIdle()
        #expect(destination.opened.map(\.url) == ["https://example.com/a/path?q=secret"])
        let match = destination.showTab("https://example.com/a/path?q=secret", in: workProfile, space: devSpace)

        coordinator.receive(link("HTTPS://Example.com/a/path/?utm_source=mail&q=secret#frag"))
        await coordinator.waitUntilIdle()

        #expect(destination.opened.count == 1)
        #expect(destination.focused.map(\.match) == [match])
        #expect(destination.focused.map(\.link) == ["HTTPS://Example.com/a/path/?utm_source=mail&q=secret#frag"])
    }

    @Test func aRuleThatForcesANewTabOpensItEvenWhenTheLinkIsOpen() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        destination.showTab("https://example.com/a/path?q=secret", in: workProfile, space: devSpace)
        let rule = LinkRule(host: "example.com", profile: "Work", forcesNewTab: true)
        let coordinator = makeCoordinator(destination, ScriptedChooser(), rules: StubRules([rule]))

        coordinator.receive(exampleLink)
        await coordinator.waitUntilIdle()

        #expect(destination.focused.isEmpty)
        #expect(destination.opened.map(\.target) == [LinkTarget(profile: workProfile.id, forcesNewTab: true)])
    }

    @Test func withTheSettingOffTheLinkOpensANewTabEvenWhenItIsOpen() async {
        let destination = RecordingDestination(profiles: [workProfile])
        destination.showTab("https://example.com/a/path?q=secret", in: workProfile, space: devSpace)
        let coordinator = makeCoordinator(destination, ScriptedChooser(), matching: false)

        coordinator.receive(exampleLink)
        await coordinator.waitUntilIdle()

        #expect(destination.focused.isEmpty)
        #expect(destination.opened.count == 1)
    }

    // MARK: Link picker

    @Test func thePickerMarksTheProfilesWhereTheLinkIsOpenAndChoosesNothing() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        destination.showTab("https://example.com/a/path?q=secret", in: homeProfile, space: readingSpace)
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser)

        coordinator.receive(link("https://example.com/a/path/?q=secret&utm_campaign=x#frag"))
        await chooser.settle()

        #expect(chooser.markedOpen == [[homeProfile.id]])
        #expect(destination.opened.isEmpty)
        #expect(destination.focused.isEmpty)

        chooser.answer(nil)
        await coordinator.waitUntilIdle()
        #expect(destination.opened.isEmpty)
        #expect(destination.focused.isEmpty)
    }

    @Test func choosingAMarkedProfileFocusesItsTabAndChoosingAnotherOpensANewTab() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let match = destination.showTab("https://example.com/a/path?q=secret", in: homeProfile, space: readingSpace)
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(homeProfile.id)
        await coordinator.waitUntilIdle()
        #expect(destination.focused.map(\.match) == [match])
        #expect(destination.opened.isEmpty)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(workProfile.id)
        await coordinator.waitUntilIdle()
        #expect(destination.opened.map(\.target.profile) == [workProfile.id])
        #expect(destination.focused.count == 1)
    }

    @Test func thePickerMarksNothingWhenTheSettingIsOffOrAfterAnAddressNobodyShows() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        destination.showTab("https://example.com/a/path?q=secret", in: homeProfile, space: readingSpace)
        let chooser = ScriptedChooser()

        let off = makeCoordinator(destination, chooser, matching: false)
        off.receive(exampleLink)
        await chooser.settle()
        chooser.answer(nil)
        await off.waitUntilIdle()

        let on = makeCoordinator(destination, chooser)
        on.receive(link("https://example.com/other"))
        await chooser.settle()
        chooser.answer(nil)
        await on.waitUntilIdle()

        #expect(chooser.markedOpen == [[], []])
    }

    @Test func choosingAMarkedProfileStillFeedsTheChoiceLog() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)/link-choices.jsonl")
        let log = LinkChoiceLog(file: file, isEnabled: true)
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        destination.showTab("https://example.com/a/path?q=secret", in: homeProfile, space: readingSpace)
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser, choiceLog: log)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(homeProfile.id)
        await coordinator.waitUntilIdle()

        let line = try String(contentsOf: file, encoding: .utf8)
        #expect(line.contains(homeProfile.id.rawValue.uuidString))
        #expect(!line.contains("secret"))
    }
}

@Suite struct MatchingTabSettingsTests {
    @Test func theSettingIsOnUntilTheUserTurnsItOff() {
        #expect(MatchingTabSettings().isEnabled)
        #expect(MatchingTabSettingsStore(store: InMemoryKeyValueStore()).load(unreadable: { _ in }).isEnabled)
    }

    @Test func theSettingIsKeptAcrossLaunches() {
        let store = InMemoryKeyValueStore()
        MatchingTabSettingsStore(store: store).save(MatchingTabSettings(isEnabled: false))
        #expect(!MatchingTabSettingsStore(store: store).load(unreadable: { _ in }).isEnabled)
        MatchingTabSettingsStore(store: store).save(MatchingTabSettings(isEnabled: true))
        #expect(MatchingTabSettingsStore(store: store).load(unreadable: { _ in }).isEnabled)
    }

    @Test func aSettingTheOldStoreTurnedOffStaysOffAfterTheMigration() throws {
        let domain = "safira-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(false, forKey: "linkMatching.focusOpenTab")

        LegacyPreference.migrate([MatchingTabSettingsStore.legacy], in: defaults, domain: domain)

        #expect(MatchingTabSettingsStore(store: defaults).load(unreadable: { _ in }).isEnabled == false)
    }

    @Test func theDefaultIsListedInTheRegistryOfDefaults() throws {
        let entry = try #require(MatchingTabSettings.defaultEntries.first)
        #expect(entry.id == "linkMatching.focusOpenTab")
        #expect(entry.title == "Focus an Open Tab Instead of Opening a Duplicate")
        #expect(entry.value == "On")
        #expect(entry.whereToChange == "Safira menu")
        #expect(MatchingTabSettings.defaultEntries.count == 1)
    }
}
