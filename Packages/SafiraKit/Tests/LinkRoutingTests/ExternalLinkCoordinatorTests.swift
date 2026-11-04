// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import SafiraCore
import Testing

@MainActor
private func makeLog(enabled: Bool) -> (LinkChoiceLog, URL) {
    let file = FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)/link-choices.jsonl")
    return (LinkChoiceLog(file: file, isEnabled: enabled), file)
}

@MainActor
@Suite struct ExternalLinkCoordinatorTests {
    @Test func aLinkWithOneProfileOpensThereWithoutAsking() async {
        let destination = RecordingDestination(profiles: [workProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser)

        coordinator.receive(exampleLink)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.url) == ["https://example.com/a/path?q=secret#frag"])
        #expect(destination.opened.map(\.target.profile) == [workProfile.id])
        #expect(chooser.asked.isEmpty)
    }

    @Test func aLinkWithSeveralProfilesOpensInTheOneTheUserChooses() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser)

        coordinator.receive(exampleLink)
        await chooser.settle()
        #expect(destination.opened.isEmpty)
        #expect(chooser.offered == [[workProfile, homeProfile]])

        chooser.answer(homeProfile.id)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.target.profile) == [homeProfile.id])
    }

    @Test func dismissingTheQuestionOpensNothing() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(nil)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.isEmpty)
    }

    @Test func aLinkThatArrivesWhileTheQuestionIsOpenWaitsForItsTurn() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser)
        let second = IncomingLink(url: URL(string: "https://swift.org/")!)

        coordinator.receive(exampleLink)
        await chooser.settle()
        coordinator.receive(second)
        await chooser.settle()
        #expect(chooser.asked.map(\.url.host) == ["example.com"])

        chooser.answer(workProfile.id)
        await chooser.settle()
        #expect(chooser.asked.map(\.url.host) == ["example.com", "swift.org"])
        chooser.answer(homeProfile.id)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.url) == ["https://example.com/a/path?q=secret#frag", "https://swift.org/"])
        #expect(destination.opened.map(\.target.profile) == [workProfile.id, homeProfile.id])
    }

    @Test func aProfileDeletedWhileTheQuestionWasOpenReceivesNothing() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let (log, file) = makeLog(enabled: true)
        let coordinator = makeCoordinator(destination, chooser, choiceLog: log)

        coordinator.receive(exampleLink)
        await chooser.settle()
        destination.profiles = [workProfile]
        chooser.answer(homeProfile.id)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    // MARK: Link rules, native apps and the Space

    @Test func aMatchingRuleOpensTheLinkWithoutAsking() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser, rules: StubRules([LinkRule(host: "example.com", profile: "Home")]))

        coordinator.receive(exampleLink)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.url) == ["https://example.com/a/path?q=secret#frag"])
        #expect(destination.opened.map(\.target) == [LinkTarget(profile: homeProfile.id)])
        #expect(chooser.asked.isEmpty)
    }

    @Test func aRuleOpensTheLinkInItsSpaceAndCanForceANewTab() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let rule = LinkRule(host: "example.com", profile: "Work", space: "Docs", forcesNewTab: true)
        let coordinator = makeCoordinator(destination, chooser, rules: StubRules([rule]))

        coordinator.receive(exampleLink)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.target) == [LinkTarget(profile: workProfile.id, space: docsSpace.id, forcesNewTab: true)])
    }

    @Test func aLinkOfAnInstalledAppOpensInTheAppAndNotInSafira() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let applications = StubApplications(installed: [.notion])
        let coordinator = makeCoordinator(destination, chooser, applications: applications)

        coordinator.receive(link("https://www.notion.so/acme/Plan-1"))
        await coordinator.waitUntilIdle()

        #expect(applications.opened.map(\.url) == ["notion://www.notion.so/acme/Plan-1"])
        #expect(applications.opened.map(\.bundleIdentifier) == ["notion.id"])
        #expect(destination.opened.isEmpty)
        #expect(chooser.asked.isEmpty)
    }

    @Test func aLinkOfAnAppThatIsNotInstalledGoesToTheLinkPicker() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let applications = StubApplications(installed: [])
        let coordinator = makeCoordinator(destination, chooser, applications: applications)

        coordinator.receive(link("https://www.notion.so/acme/Plan-1"))
        await chooser.settle()

        #expect(chooser.asked.map(\.url.host) == ["www.notion.so"])
        #expect(applications.opened.isEmpty)
        chooser.answer(nil)
        await coordinator.waitUntilIdle()
    }

    @Test func whenTheAppRefusesTheLinkTheRulesDecide() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let applications = StubApplications(installed: [.figma], accepts: false)
        let rules = StubRules([LinkRule(host: "figma.com", profile: "Work")])
        let coordinator = makeCoordinator(destination, chooser, rules: rules, applications: applications)

        coordinator.receive(link("https://www.figma.com/design/AbC/Landing"))
        await coordinator.waitUntilIdle()

        #expect(applications.opened.count == 1)
        #expect(destination.opened.map(\.target.profile) == [workProfile.id])
    }

    @Test func whenTheAppRefusesTheLinkAndNoRuleMatchesTheLinkPickerAsks() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser, applications: StubApplications(installed: [.figma], accepts: false))

        coordinator.receive(link("https://www.figma.com/design/AbC/Landing"))
        await chooser.settle()

        #expect(chooser.asked.count == 1)
        chooser.answer(homeProfile.id)
        await coordinator.waitUntilIdle()
        #expect(destination.opened.map(\.target.profile) == [homeProfile.id])
    }

    @Test func aSlackLinkWithoutTheGrantFallsBackToTheRulesWithoutAnyError() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let applications = StubApplications(installed: [.slack])
        let reporter = RecordingReporter()
        let rules = StubRules([LinkRule(host: "slack.com", profile: "Work")])
        let coordinator = makeCoordinator(destination, chooser, rules: rules, applications: applications, reporter: reporter)

        coordinator.receive(link("https://acme.slack.com/archives/C0CHANNEL1"))
        await coordinator.waitUntilIdle()

        #expect(applications.opened.isEmpty)
        #expect(destination.opened.map(\.target.profile) == [workProfile.id])
        #expect(reporter.invalidFiles.isEmpty)
        #expect(reporter.skipped.isEmpty)
    }

    @Test func aSlackLinkWithoutTheGrantAndWithoutARuleGoesToTheLinkPicker() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser, applications: StubApplications(installed: [.slack]))

        coordinator.receive(link("https://acme.slack.com/archives/C0CHANNEL1"))
        await chooser.settle()

        #expect(chooser.asked.count == 1)
        chooser.answer(nil)
        await coordinator.waitUntilIdle()
    }

    @Test func aSlackLinkWithTheGrantOpensInSlack() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let applications = StubApplications(installed: [.slack])
        let coordinator = makeCoordinator(destination, chooser, applications: applications, slack: StubSlack(teams: ["acme": "T0ACME1"]))

        coordinator.receive(link("https://acme.slack.com/archives/C0CHANNEL1/p1712345678123456"))
        await coordinator.waitUntilIdle()

        #expect(applications.opened.map(\.url) == ["slack://channel?team=T0ACME1&id=C0CHANNEL1&message=1712345678.123456"])
        #expect(applications.opened.map(\.bundleIdentifier) == ["com.tinyspeck.slackmacgap"])
        #expect(destination.opened.isEmpty)
    }

    @Test func anInvalidRulesFileIsReportedAndTheLinkPickerAsks() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let reporter = RecordingReporter()
        let coordinator = makeCoordinator(destination, chooser, rules: StubRules(invalid: .invalidField(location: "rules[0].profile")),
                                          reporter: reporter)

        coordinator.receive(exampleLink)
        await chooser.settle()

        #expect(reporter.invalidFiles == [.invalidField(location: "rules[0].profile")])
        #expect(chooser.asked.count == 1)
        chooser.answer(workProfile.id)
        await coordinator.waitUntilIdle()
        #expect(destination.opened.map(\.target.profile) == [workProfile.id])
    }

    @Test func theLinkPickerDoesNotAskForTheSpaceByDefault() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(workProfile.id)
        await coordinator.waitUntilIdle()

        #expect(chooser.spacesAsked.isEmpty)
        #expect(destination.opened.map(\.target) == [LinkTarget(profile: workProfile.id)])
    }

    @Test func withTheOptionOnTheLinkPickerAsksForTheSpaceOfTheChosenProfile() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser, asksForSpace: true)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(workProfile.id)
        await chooser.settle()
        #expect(destination.opened.isEmpty)
        #expect(chooser.spacesAsked.map(\.profile) == [workProfile.id])
        #expect(chooser.spacesAsked.first?.spaces == [devSpace, docsSpace])

        chooser.answerSpace(docsSpace.id)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.target) == [LinkTarget(profile: workProfile.id, space: docsSpace.id)])
    }

    @Test func dismissingTheSpaceQuestionOpensNothing() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let (log, file) = makeLog(enabled: true)
        let coordinator = makeCoordinator(destination, chooser, choiceLog: log, asksForSpace: true)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(workProfile.id)
        await chooser.settle()
        chooser.answerSpace(nil)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test func aProfileWithOneSpaceIsNotAskedForIt() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser, asksForSpace: true)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(homeProfile.id)
        await coordinator.waitUntilIdle()

        #expect(chooser.spacesAsked.isEmpty)
        #expect(destination.opened.map(\.target) == [LinkTarget(profile: homeProfile.id)])
    }

    @Test func aRuleThatNamesASpaceNeverAsksForIt() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let rule = LinkRule(host: "example.com", profile: "Work", space: "Dev")
        let coordinator = makeCoordinator(destination, chooser, rules: StubRules([rule]), asksForSpace: true)

        coordinator.receive(exampleLink)
        await coordinator.waitUntilIdle()

        #expect(chooser.asked.isEmpty)
        #expect(chooser.spacesAsked.isEmpty)
        #expect(destination.opened.map(\.target) == [LinkTarget(profile: workProfile.id, space: devSpace.id)])
    }

    @Test func theOptionIsReadForEachLink() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        var asks = false
        let coordinator = ExternalLinkCoordinator(
            destination: destination, chooser: chooser, router: makeRouter(),
            nativeApplications: StubApplications(), asksForSpace: { asks })

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(workProfile.id)
        await coordinator.waitUntilIdle()
        asks = true
        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(workProfile.id)
        await chooser.settle()

        #expect(chooser.spacesAsked.count == 1)
        chooser.answerSpace(devSpace.id)
        await coordinator.waitUntilIdle()
    }

    @Test(arguments: ["mailto:someone@example.com", "slack://open", "ftp://example.com/file"])
    func linksSafiraDoesNotHandleAreDropped(address: String) async throws {
        let destination = RecordingDestination(profiles: [workProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser)

        coordinator.receive(IncomingLink(url: try #require(URL(string: address))))
        await coordinator.waitUntilIdle()

        #expect(destination.opened.isEmpty)
        #expect(chooser.asked.isEmpty)
    }

    @Test func aLocalHTMLFileGoesThroughTheSameChoice() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = makeCoordinator(destination, chooser)

        coordinator.receive(IncomingLink(url: URL(filePath: "/Users/someone/page.html")))
        await chooser.settle()
        chooser.answer(workProfile.id)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.url) == ["file:///Users/someone/page.html"])
    }

    @Test func aChoiceIsLoggedWithTheHostAndTheProfileOnlyWhenTheLogIsOn() async throws {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let (log, file) = makeLog(enabled: true)
        let coordinator = makeCoordinator(destination, chooser, choiceLog: log)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(workProfile.id)
        await coordinator.waitUntilIdle()

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written == "{\"host\":\"example.com\",\"profile\":\"11111111-1111-4111-8111-111111111111\"}\n")
    }

    @Test func nothingIsLoggedWhileTheLogIsOff() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let (log, file) = makeLog(enabled: false)
        let coordinator = makeCoordinator(destination, chooser, choiceLog: log)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(workProfile.id)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.target.profile) == [workProfile.id])
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }
}
