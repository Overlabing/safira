// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import SafiraCore
import Testing

/// Everything the Link rules window and the Link picker's "always" touch, on a real rules file in a temporary folder.
@MainActor
private struct Harness {
    let url: URL
    let store: LinkRulesStore
    let destination: RecordingDestination
    let chooser = ScriptedChooser()
    let reporter = RecordingReporter()
    let coordinator: ExternalLinkCoordinator
    let model: LinkRulesModel
    var failures: Failures

    @MainActor
    final class Failures {
        var errors: [LinkRulesEditError] = []
        /// The open Link rules window, which reads the file again when a rule is added behind its back.
        weak var window: LinkRulesModel?
    }

    init(file: String? = nil, profiles: [Profile] = [workProfile, homeProfile], asksForSpace: Bool = false) throws {
        url = try temporaryRulesFile()
        if let file { try Data(file.utf8).write(to: url) }
        store = LinkRulesStore(url: url)
        destination = RecordingDestination(profiles: profiles)
        let failures = Failures()
        self.failures = failures
        let applications = StubApplications()
        let router = LinkRouter(rules: LinkRulesFile(url: url),
                                nativeApps: NativeAppLinks(applications: applications, slack: StubSlack()),
                                reporter: reporter)
        coordinator = ExternalLinkCoordinator(
            destination: destination, chooser: chooser, router: router, nativeApplications: applications,
            rememberer: StoredLinkRuleRemembering(store: store, didFail: { failures.errors.append($0) },
                                                  didAdd: { failures.window?.reload() }),
            asksForSpace: { asksForSpace })
        let coordinator = coordinator
        let destination = destination
        model = LinkRulesModel(store: store, profiles: { destination.profiles }, spacesOf: { destination.spaces(in: $0) },
                               route: { coordinator.route(for: $0) })
        failures.window = model
    }

    func deliver(_ address: String, from opener: String? = nil) async {
        coordinator.receive(link(address, from: opener))
        await chooser.settle()
    }
}

@MainActor private func hosts(_ model: LinkRulesModel) -> [String] {
    model.entries.map { $0.rule.host ?? "-" }
}

@MainActor
@Suite struct AlwaysInTheLinkPickerTests {
    @Test func alwaysThenTheNextLinkFromTheSiteRoutesWithoutAsking() async throws {
        let harness = try Harness()

        await harness.deliver("https://shop.example/cart")
        harness.chooser.answer(homeProfile.id, always: true)
        await harness.coordinator.waitUntilIdle()
        #expect(harness.destination.opened.map(\.target.profile) == [homeProfile.id])
        #expect(harness.chooser.asked.count == 1)

        await harness.deliver("https://shop.example/orders/12")
        await harness.coordinator.waitUntilIdle()

        #expect(harness.chooser.asked.count == 1)
        #expect(harness.destination.opened.map(\.url) == ["https://shop.example/cart", "https://shop.example/orders/12"])
        #expect(harness.destination.opened.map(\.target.profile) == [homeProfile.id, homeProfile.id])
        #expect(harness.model.entries.map(\.match) == ["shop.example"])
    }

    @Test func theRuleNamesTheProfileByIdentifierSoRenamingItKeepsTheRule() async throws {
        let harness = try Harness()
        await harness.deliver("https://shop.example/")
        harness.chooser.answer(homeProfile.id, always: true)
        await harness.coordinator.waitUntilIdle()

        guard case .rules(let set) = harness.store.load() else { Issue.record("not valid"); return }
        #expect(set.rules == [LinkRule(host: "shop.example", profile: "22222222-2222-4222-8222-222222222222")])
        #expect(harness.model.entries.map(\.destination) == ["Home"])
    }

    @Test func withoutAlwaysNoRuleIsCreatedAndTheNextLinkAsksAgain() async throws {
        let harness = try Harness()
        await harness.deliver("https://shop.example/")
        harness.chooser.answer(homeProfile.id)
        await harness.coordinator.waitUntilIdle()

        await harness.deliver("https://shop.example/again")

        #expect(harness.chooser.asked.count == 2)
        #expect(harness.store.load() == .rules(.empty))
    }

    @Test func dismissingThePickerCreatesNoRuleEvenWithAlwaysOn() async throws {
        let harness = try Harness()
        await harness.deliver("https://shop.example/")
        harness.chooser.answer(nil, always: true)
        await harness.coordinator.waitUntilIdle()

        #expect(harness.store.load() == .rules(.empty))
        #expect(harness.destination.opened.isEmpty)
    }

    @Test func alwaysInTheSpaceStepRemembersTheSpaceToo() async throws {
        let harness = try Harness(asksForSpace: true)
        await harness.deliver("https://docs.example/guide")
        harness.chooser.answer(workProfile.id, always: true)
        await harness.chooser.settle()
        #expect(harness.chooser.rememberingAtSpaceStep == [true])
        harness.chooser.answerSpace(docsSpace.id, always: true)
        await harness.coordinator.waitUntilIdle()

        guard case .rules(let set) = harness.store.load() else { Issue.record("not valid"); return }
        #expect(set.rules == [LinkRule(host: "docs.example", profile: "11111111-1111-4111-8111-111111111111",
                                       space: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")])

        await harness.deliver("https://docs.example/other")
        await harness.coordinator.waitUntilIdle()
        #expect(harness.destination.opened.last?.target == LinkTarget(profile: workProfile.id, space: docsSpace.id))
        #expect(harness.chooser.asked.count == 1)
    }

    @Test func turningAlwaysOffInTheSpaceStepCreatesNoRule() async throws {
        let harness = try Harness(asksForSpace: true)
        await harness.deliver("https://docs.example/guide")
        harness.chooser.answer(workProfile.id, always: true)
        await harness.chooser.settle()
        harness.chooser.answerSpace(devSpace.id, always: false)
        await harness.coordinator.waitUntilIdle()

        #expect(harness.store.load() == .rules(.empty))
    }

    @Test func aRuleAddedByAlwaysGoesAfterTheExistingOnesSoTheyKeepWinning() async throws {
        let harness = try Harness(file: """
            {"version": 1, "rules": [{"host": "shop.example", "path": "/work", "profile": "Work"}]}
            """)
        await harness.deliver("https://shop.example/other")
        harness.chooser.answer(homeProfile.id, always: true)
        await harness.coordinator.waitUntilIdle()

        await harness.deliver("https://shop.example/work/orders")
        await harness.coordinator.waitUntilIdle()

        #expect(harness.model.entries.map(\.match) == ["shop.example/work", "shop.example"])
        #expect(harness.destination.opened.last?.target.profile == workProfile.id)
        #expect(harness.chooser.asked.count == 1)
    }

    @Test func alwaysDoesNotOverwriteAnInvalidRulesFileAndReportsIt() async throws {
        let harness = try Harness(file: "{ the user is mid-edit")
        await harness.deliver("https://shop.example/")
        harness.chooser.answer(homeProfile.id, always: true)
        await harness.coordinator.waitUntilIdle()

        #expect(try Data(contentsOf: harness.url) == Data("{ the user is mid-edit".utf8))
        #expect(harness.failures.errors == [.existingFileInvalid(.notJSON)])
        // The link itself still opened where the user chose.
        #expect(harness.destination.opened.map(\.target.profile) == [homeProfile.id])
    }

    @Test func aLocalFileOffersNoAlwaysAndLeavesNoRule() async throws {
        let harness = try Harness()
        await harness.deliver("file:///tmp/page.html")
        harness.chooser.answer(homeProfile.id, always: true)
        await harness.coordinator.waitUntilIdle()

        #expect(harness.store.load() == .rules(.empty))
    }
}

@MainActor
@Suite struct LinkRulesListTests {
    private let file = """
        {"version": 1, "rules": [
          {"host": "alpha.example", "profile": "Work", "space": "Dev"},
          {"host": "beta.example", "path": "/team", "profile": "Home", "newTab": true},
          {"opener": "com.example.chat", "profile": "Nobody"},
          {"profile": "Work"}
        ]}
        """

    @Test func theRulesAreListedInOrderWithWhereEachOneGoesAndWhyOneCannotApply() throws {
        let model = try Harness(file: file).model

        #expect(model.entries.map(\.position) == [1, 2, 3, 4])
        #expect(model.entries.map(\.match) == ["alpha.example", "beta.example/team", "from com.example.chat", "(no host or Opener)"])
        #expect(model.entries.map(\.destination) == ["Work › Dev", "Home", "Nobody", "Work"])
        #expect(model.entries.map(\.problem) == [nil, nil, "Skipped: no such Profile", "Ignored: it has no host and no Opener"])
        #expect(model.entries[1].accessibilityLabel == "Rule 2, beta.example/team → Home, always a new Tab")
        #expect(model.entries[2].accessibilityLabel == "Rule 3, from com.example.chat → Nobody, Skipped: no such Profile")
    }

    @Test func deletingTheSelectedRuleRemovesItAndSelectsTheOneThatTookItsPlace() throws {
        let model = try Harness(file: file).model
        model.selection = 2

        model.deleteSelected()

        #expect(hosts(model) == ["alpha.example", "-", "-"])
        #expect(model.selection == 2)
        #expect(model.message == LinkRulesMessage(text: "Deleted rule 2, beta.example/team.", isError: false))
    }

    @Test func deletingTheLastRuleSelectsThePreviousOneAndTheOnlyRuleSelectsNothing() throws {
        let model = try Harness(file: #"{"version":1,"rules":[{"host":"a.example","profile":"Work"},{"host":"b.example","profile":"Work"}]}"#).model
        model.selection = 2
        model.deleteSelected()
        #expect(model.selection == 1)
        model.deleteSelected()
        #expect(model.entries.isEmpty)
        #expect(model.selection == nil)
    }

    @Test func movingARuleChangesWhichOneWinsAndTheSelectionFollowsIt() async throws {
        let harness = try Harness(file: """
            {"version": 1, "rules": [
              {"host": "example.com", "profile": "Work"},
              {"host": "example.com", "profile": "Home"}
            ]}
            """)
        let model = harness.model
        model.checkedAddress = "https://example.com/page"
        model.runCheck()
        #expect(model.checkResult == "It opens in a new Tab of Work, in its last active Space. Rule 1 decided it.")

        model.selection = 2
        #expect(model.canMoveUp)
        #expect(!model.canMoveDown)
        model.moveSelected(by: -1)

        #expect(model.selection == 1)
        #expect(model.entries.map(\.destination) == ["Home", "Work"])
        model.runCheck()
        #expect(model.checkResult == "It opens in a new Tab of Home, in its last active Space. Rule 1 decided it.")
        await harness.deliver("https://example.com/page")
        await harness.coordinator.waitUntilIdle()
        #expect(harness.destination.opened.map(\.target.profile) == [homeProfile.id])
    }

    @Test func movingPastEitherEndDoesNothing() throws {
        let model = try Harness(file: file).model
        model.selection = 1
        #expect(!model.canMoveUp)
        model.moveSelected(by: -1)
        #expect(hosts(model) == ["alpha.example", "beta.example", "-", "-"])
        #expect(model.message == nil)
    }

    @Test func anInvalidFileIsShownAsSuchAndCannotBeEditedFromTheWindow() throws {
        let harness = try Harness(file: "{ broken")
        let model = harness.model

        #expect(model.fileProblem == .notJSON)
        #expect(model.entries.isEmpty)
        #expect(!model.canEdit)
        model.importFile(Data(#"{"version":1,"rules":[]}"#.utf8), mode: .replace)
        #expect(model.message?.isError == true)
        #expect(try Data(contentsOf: harness.url) == Data("{ broken".utf8))
    }

    @Test func aHandEditIsPickedUpWhenTheListIsReloaded() throws {
        let harness = try Harness()
        #expect(harness.model.entries.isEmpty)
        try Data(file.utf8).write(to: harness.url)

        harness.model.reload()

        #expect(harness.model.entries.count == 4)
    }
}

@MainActor
@Suite struct LinkRulesImportExportTests {
    private let source = #"{"version":1,"rules":[{"host":"a.example","profile":"Work"},{"host":"b.example","profile":"Home"}]}"#

    @Test func exportedRulesImportIntoAnotherInstallWithTheSameRulesInTheSameOrder() throws {
        let exporting = try Harness(file: source).model
        let exported = try #require(exporting.exportData())
        #expect(exporting.message == LinkRulesMessage(text: "Exported 2 rules.", isError: false))

        let importing = try Harness().model
        importing.importFile(exported, mode: .replace)

        #expect(importing.entries.map(\.rule) == exporting.entries.map(\.rule))
        #expect(importing.message == LinkRulesMessage(text: "Imported 2 rules.", isError: false))
    }

    @Test func anInvalidImportIsReportedAndEveryExistingRuleStays() throws {
        let harness = try Harness(file: source)

        harness.model.importFile(Data(#"{"version":1,"rules":[{"host":"c.example"}]}"#.utf8), mode: .addToEnd)

        #expect(harness.model.message == LinkRulesMessage(
            text: "The file is not a valid Link rules file. \"rules[0].profile\" is missing or has the wrong type.", isError: true))
        #expect(hosts(harness.model) == ["a.example", "b.example"])
        #expect(try Data(contentsOf: harness.url) == Data(source.utf8))
    }

    @Test func importingToTheEndAddsAfterTheExistingRules() throws {
        let model = try Harness(file: source).model
        model.importFile(Data(#"{"version":1,"rules":[{"host":"c.example","profile":"Work"}]}"#.utf8), mode: .addToEnd)
        #expect(hosts(model) == ["a.example", "b.example", "c.example"])
        #expect(model.message == LinkRulesMessage(text: "Imported 1 rules.", isError: false))
    }

    @Test func aZenPickerFileIsImportedWithEachTargetMappedToAProfile() throws {
        let model = try Harness(file: source).model
        let zen = Data(#"[{"host":"c.example","target":"first"},{"host":"d.example","path":"/x","target":"second"},{"host":"e.example","target":"third"}]"#.utf8)

        #expect(try model.zenPickerTargets(in: zen).get() == ["first", "second", "third"])
        model.importZenPicker(zen, profileFor: ["first": workProfile.id, "second": homeProfile.id])

        #expect(model.entries.map(\.match) == ["a.example", "b.example", "c.example", "d.example/x"])
        #expect(model.entries.map(\.destination) == ["Work", "Home", "Work", "Home"])
        #expect(model.message == LinkRulesMessage(
            text: "Imported 2 rules; left out 1 without a Profile or without a host or Opener.", isError: false))
    }

    @Test func aFileThatIsNotZenPickerRulesIsRefusedAndNothingChanges() throws {
        let harness = try Harness(file: source)
        harness.model.importZenPicker(Data(source.utf8), profileFor: [:])
        #expect(harness.model.message?.isError == true)
        #expect(try Data(contentsOf: harness.url) == Data(source.utf8))
    }
}

@MainActor
@Suite struct WhereWouldThisLinkGoTests {
    private let file = """
        {"version": 1, "rules": [
          {"host": "docs.example", "profile": "Work", "space": "Docs"},
          {"host": "forced.example", "profile": "Home", "newTab": true},
          {"opener": "com.example.chat", "profile": "Home"},
          {"host": "stale.example", "profile": "Nobody"}
        ]}
        """

    /// What the check says must be what real delivery does, for each of these links.
    @Test(arguments: [
        ("https://docs.example/guide", nil as String?),
        ("https://forced.example/", nil),
        ("https://unmatched.example/", "com.example.chat"),
        ("https://unmatched.example/", nil),
        ("https://stale.example/", nil),
    ])
    func theCheckGivesTheDecisionTheRealLinkGets(address: String, opener: String?) async throws {
        let harness = try Harness(file: file)
        let checked = harness.coordinator.route(for: link(address, from: opener))

        await harness.deliver(address, from: opener)
        if checked.decision == .ask {
            #expect(harness.chooser.asked.count == 1)
            harness.chooser.answer(nil)
        } else if case .open(let target) = checked.decision {
            #expect(harness.destination.opened.map(\.target) == [target])
            #expect(harness.chooser.asked.isEmpty)
        } else {
            Issue.record("unexpected decision \(checked.decision)")
        }
        await harness.coordinator.waitUntilIdle()
    }

    @Test func theCheckNamesTheProfileTheSpaceAndTheRule() throws {
        let model = try Harness(file: file).model
        model.checkedAddress = "docs.example/guide"
        model.runCheck()
        #expect(model.checkResult == "It opens in a new Tab of Work, in the Space Docs. Rule 1 decided it.")

        model.checkedAddress = "https://forced.example/x"
        model.runCheck()
        #expect(model.checkResult == "It opens in a new Tab of Home, in its last active Space. The rule asks for a new Tab even if the link is already open. Rule 2 decided it.")

        model.checkedAddress = "https://unmatched.example/"
        model.runCheck()
        #expect(model.checkResult == "Safira asks which Profile receives it.")

        model.checkedOpener = "com.example.chat"
        model.runCheck()
        #expect(model.checkResult == "It opens in a new Tab of Home, in its last active Space. Rule 3 decided it.")
    }

    @Test func aRuleThatCannotBeResolvedIsSkippedByTheCheckAsByRealRouting() throws {
        let model = try Harness(file: file).model
        model.checkedAddress = "https://stale.example/"
        model.runCheck()
        #expect(model.checkResult == "Safira asks which Profile receives it.")
    }

    @Test func theCheckShowsTheTabItWouldFocus() throws {
        let harness = try Harness(file: file)
        harness.destination.showTab("https://docs.example/guide", in: workProfile, space: docsSpace)
        harness.model.checkedAddress = "https://docs.example/guide"
        harness.model.runCheck()
        #expect(harness.model.checkResult == "It shows the Tab that already has this address, in Work, Space Docs. Rule 1 decided it.")
    }

    @Test func checkingAnInvalidFileDoesNotReportItButSaysNoRuleApplies() throws {
        let harness = try Harness(file: "{ broken")
        harness.model.checkedAddress = "https://docs.example/"
        harness.model.runCheck()

        #expect(harness.model.checkResult == "The Link rules file is not valid, so no rule applies. The file is not valid JSON. Safira asks which Profile receives it.")
        #expect(harness.reporter.invalidFiles.isEmpty)
    }

    @Test func theCheckAnswersOnlyForWebLinks() throws {
        let model = try Harness(file: file).model
        model.checkedAddress = ""
        model.runCheck()
        #expect(model.checkResult == "Type or paste a link first.")
        model.checkedAddress = "mailto:someone@example.com"
        model.runCheck()
        #expect(model.checkResult == "That is not a web link.")
    }
}
