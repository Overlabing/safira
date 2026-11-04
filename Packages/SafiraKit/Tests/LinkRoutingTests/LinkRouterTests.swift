// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import SafiraCore
import Testing

let workProfile = Profile(id: ProfileID(uuidString: "11111111-1111-4111-8111-111111111111")!, name: "Work", symbol: "💼")
let homeProfile = Profile(id: ProfileID(uuidString: "22222222-2222-4222-8222-222222222222")!, name: "Home", symbol: "🏡")
let exampleLink = IncomingLink(url: URL(string: "https://example.com/a/path?q=secret#frag")!)

@MainActor
private func decide(_ link: IncomingLink, profiles: [Profile] = [workProfile, homeProfile], router: LinkRouter? = nil,
                    includingNativeApps: Bool = true) -> LinkDecision {
    (router ?? makeRouter()).decide(for: link, among: profiles, spacesOf: { defaultSpaces[$0] ?? [] },
                                    includingNativeApps: includingNativeApps)
}

@MainActor
@Suite struct LinkRouterTests {
    @Test func aSingleProfileReceivesTheLinkWithoutAsking() {
        #expect(decide(exampleLink, profiles: [workProfile]) == .open(LinkTarget(profile: workProfile.id)))
    }

    @Test func severalProfilesMeanTheUserChooses() {
        #expect(decide(exampleLink) == .ask)
    }

    // MARK: Link rules

    @Test func aMatchingRuleSendsTheLinkToItsProfileWithoutAsking() {
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Home")]))
        #expect(decide(exampleLink, router: router) == .open(LinkTarget(profile: homeProfile.id)))
    }

    @Test func aProfileIsFoundByItsIdentifierFirst() {
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "22222222-2222-4222-8222-222222222222")]))
        #expect(decide(exampleLink, router: router) == .open(LinkTarget(profile: homeProfile.id)))
    }

    @Test func aProfileIsFoundByItsExactNameWhenNoIdentifierMatches() {
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work")]))
        #expect(decide(exampleLink, router: router) == .open(LinkTarget(profile: workProfile.id)))
    }

    @Test func aProfileNameIsNotMatchedLoosely() {
        let reporter = RecordingReporter()
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "work")]), reporter: reporter)
        #expect(decide(exampleLink, router: router) == .ask)
        #expect(reporter.skipped.map(\.problem) == [.unknownProfile])
    }

    @Test func theIdentifierWinsOverAProfileNamedLikeAnotherProfilesIdentifier() {
        let confusing = Profile(id: ProfileID(uuidString: "33333333-3333-4333-8333-333333333333")!,
                                name: "11111111-1111-4111-8111-111111111111")
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: confusing.name)]))
        #expect(decide(exampleLink, profiles: [workProfile, confusing], router: router) == .open(LinkTarget(profile: workProfile.id)))
    }

    @Test func theFirstMatchingRuleWins() {
        let router = makeRouter(rules: StubRules([
            LinkRule(host: "other.com", profile: "Work"),
            LinkRule(host: "example.com", profile: "Home"),
            LinkRule(host: "example.com", profile: "Work"),
        ]))
        #expect(decide(exampleLink, router: router) == .open(LinkTarget(profile: homeProfile.id)))
    }

    @Test func aRuleWithNeitherHostNorOpenerIsIgnoredAndTheNextOneApplies() {
        let router = makeRouter(rules: StubRules([
            LinkRule(path: "/a", profile: "Home"),
            LinkRule(host: "example.com", profile: "Work"),
        ]))
        #expect(decide(exampleLink, router: router) == .open(LinkTarget(profile: workProfile.id)))
    }

    @Test func aRuleMatchesTheOpenerOfTheLink() {
        let router = makeRouter(rules: StubRules([LinkRule(opener: "com.tinyspeck.slackmacgap", profile: "Home")]))
        #expect(decide(link("https://swift.org/", from: "com.tinyspeck.slackmacgap"), router: router)
            == .open(LinkTarget(profile: homeProfile.id)))
        #expect(decide(link("https://swift.org/", from: "com.apple.mail"), router: router) == .ask)
        #expect(decide(link("https://swift.org/"), router: router) == .ask)
    }

    @Test func noMatchingRuleLeavesTheChoiceToTheLinkPicker() {
        let router = makeRouter(rules: StubRules([LinkRule(host: "github.com", profile: "Work")]))
        #expect(decide(exampleLink, router: router) == .ask)
    }

    @Test func aRuleSendsTheLinkToAProfileEvenWhenItIsTheOnlyOne() {
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work", space: "Docs")]))
        #expect(decide(exampleLink, profiles: [workProfile], router: router)
            == .open(LinkTarget(profile: workProfile.id, space: docsSpace.id)))
    }

    // MARK: Spaces and new Tabs

    @Test func aRuleCanNameASpaceByNameOrByIdentifier() {
        let byName = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work", space: "Docs")]))
        let byID = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work", space: devSpace.id.rawValue.uuidString)]))
        #expect(decide(exampleLink, router: byName) == .open(LinkTarget(profile: workProfile.id, space: docsSpace.id)))
        #expect(decide(exampleLink, router: byID) == .open(LinkTarget(profile: workProfile.id, space: devSpace.id)))
    }

    @Test func aRuleWithoutASpaceLeavesItToTheLastActiveSpace() {
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work")]))
        #expect(decide(exampleLink, router: router) == .open(LinkTarget(profile: workProfile.id, space: nil)))
    }

    @Test func aRuleCanForceANewTab() {
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work", forcesNewTab: true)]))
        #expect(decide(exampleLink, router: router) == .open(LinkTarget(profile: workProfile.id, forcesNewTab: true)))
    }

    @Test func aRuleWithASpaceAndANewTabCarriesBoth() {
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work", space: "Dev", forcesNewTab: true)]))
        #expect(decide(exampleLink, router: router)
            == .open(LinkTarget(profile: workProfile.id, space: devSpace.id, forcesNewTab: true)))
    }

    @Test func aSpaceOfAnotherProfileIsNotFound() {
        let reporter = RecordingReporter()
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work", space: "Reading")]), reporter: reporter)
        #expect(decide(exampleLink, router: router) == .ask)
        #expect(reporter.skipped.map(\.problem) == [.unknownSpace])
    }

    @Test func spacesAreOnlyAskedForWhenARuleNamesOne() {
        var asked: [ProfileID] = []
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work")]))
        _ = router.decide(for: exampleLink, among: [workProfile, homeProfile], spacesOf: { asked.append($0); return [] })
        #expect(asked.isEmpty)
    }

    // MARK: Rules that cannot be resolved

    @Test func aRuleWhoseProfileDoesNotExistIsReportedAndTheNextRuleApplies() {
        let reporter = RecordingReporter()
        let router = makeRouter(rules: StubRules([
            LinkRule(host: "example.com", profile: "Deleted"),
            LinkRule(host: "example.com", profile: "Home"),
        ]), reporter: reporter)

        #expect(decide(exampleLink, router: router) == .open(LinkTarget(profile: homeProfile.id)))
        #expect(reporter.skipped.map(\.index) == [0])
        #expect(reporter.skipped.map(\.problem) == [.unknownProfile])
    }

    @Test func aRuleWhoseProfileCannotBeToldApartIsNeverGuessed() {
        let twin = Profile(id: ProfileID(rawValue: UUID()), name: "Work")
        let reporter = RecordingReporter()
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work")]), reporter: reporter)

        #expect(decide(exampleLink, profiles: [workProfile, twin], router: router) == .ask)
        #expect(reporter.skipped.map(\.problem) == [.ambiguousProfile])
    }

    @Test func aRuleWhoseSpaceCannotBeToldApartIsNeverGuessed() {
        let reporter = RecordingReporter()
        let router = makeRouter(rules: StubRules([LinkRule(host: "example.com", profile: "Work", space: "Dev")]), reporter: reporter)
        let twin = SpaceChoice(id: SpaceID(), name: "Dev", emoji: "🧪")

        let decision = router.decide(for: exampleLink, among: [workProfile, homeProfile], spacesOf: { _ in [devSpace, twin] })

        #expect(decision == .ask)
        #expect(reporter.skipped.map(\.problem) == [.ambiguousSpace])
    }

    @Test func aRuleThatDoesNotMatchTheLinkIsNotReported() {
        let reporter = RecordingReporter()
        let router = makeRouter(rules: StubRules([LinkRule(host: "github.com", profile: "Deleted")]), reporter: reporter)
        _ = decide(exampleLink, router: router)
        #expect(reporter.skipped.isEmpty)
    }

    // MARK: Native apps

    @Test func aLinkOfAnInstalledAppOpensInThatApp() {
        let router = makeRouter(applications: StubApplications(installed: [.linear]))
        let expected = NativeLink(app: .linear, url: URL(string: "linear://acme/issue/ABC-1")!)
        #expect(decide(link("https://linear.app/acme/issue/ABC-1"), router: router) == .openNative(expected))
    }

    @Test func theAppComesBeforeAnyRule() {
        let router = makeRouter(
            rules: StubRules([LinkRule(host: "linear.app", profile: "Work"), LinkRule(opener: "com.tinyspeck.slackmacgap", profile: "Home")]),
            applications: StubApplications(installed: [.linear]))
        let decision = decide(link("https://linear.app/acme/issue/ABC-1", from: "com.tinyspeck.slackmacgap"), router: router)
        #expect(decision == .openNative(NativeLink(app: .linear, url: URL(string: "linear://acme/issue/ABC-1")!)))
    }

    @Test func theAppComesBeforeTheSingleProfileShortcut() {
        let router = makeRouter(applications: StubApplications(installed: [.figma]))
        let decision = decide(link("https://www.figma.com/design/AbC/Landing"), profiles: [workProfile], router: router)
        #expect(decision == .openNative(NativeLink(app: .figma, url: URL(string: "figma://design/AbC/Landing")!)))
    }

    @Test func aLinkOfAnAppThatIsNotInstalledGoesToTheRules() {
        let router = makeRouter(rules: StubRules([LinkRule(host: "linear.app", profile: "Work")]),
                                applications: StubApplications(installed: []))
        #expect(decide(link("https://linear.app/acme/issue/ABC-1"), router: router) == .open(LinkTarget(profile: workProfile.id)))
    }

    @Test func aRuleFileThatTurnsTheAppOffSendsTheLinkToTheRules() {
        let router = makeRouter(rules: StubRules([LinkRule(host: "linear.app", profile: "Work")], nativeApps: [.slack, .notion, .figma]),
                                applications: StubApplications(installed: [.linear]))
        #expect(decide(link("https://linear.app/acme/issue/ABC-1"), router: router) == .open(LinkTarget(profile: workProfile.id)))
    }

    @Test func afterTheAppRefusedTheLinkTheRulesDecide() {
        let router = makeRouter(rules: StubRules([LinkRule(host: "linear.app", profile: "Work")]),
                                applications: StubApplications(installed: [.linear]))
        let decision = decide(link("https://linear.app/acme/issue/ABC-1"), router: router, includingNativeApps: false)
        #expect(decision == .open(LinkTarget(profile: workProfile.id)))
    }

    @Test func aSlackLinkGoesToTheAppOnlyWhenTheTeamIsKnown() {
        let address = "https://acme.slack.com/archives/C0CHANNEL1"
        let granted = makeRouter(applications: StubApplications(installed: [.slack]), slack: StubSlack(teams: ["acme": "T0ACME1"]))
        let notGranted = makeRouter(rules: StubRules([LinkRule(host: "acme.slack.com", profile: "Home")]),
                                    applications: StubApplications(installed: [.slack]))
        let expected = NativeLink(app: .slack, url: URL(string: "slack://channel?team=T0ACME1&id=C0CHANNEL1")!)

        #expect(decide(link(address), router: granted) == .openNative(expected))
        #expect(decide(link(address), router: notGranted) == .open(LinkTarget(profile: homeProfile.id)))
        #expect(decide(link(address), router: makeRouter(applications: StubApplications(installed: [.slack]))) == .ask)
    }

    // MARK: An invalid rules file

    @Test func anInvalidRulesFileIsReportedAndLeavesTheChoiceToTheLinkPicker() {
        let reporter = RecordingReporter()
        let router = makeRouter(rules: StubRules(invalid: .notJSON), applications: StubApplications(installed: [.linear]),
                                reporter: reporter)

        #expect(decide(exampleLink, router: router) == .ask)
        #expect(decide(link("https://linear.app/acme/issue/ABC-1"), router: router) == .ask)
        #expect(reporter.invalidFiles == [.notJSON, .notJSON])
    }

    @Test func anInvalidRulesFileStillOpensDirectlyWithASingleProfile() {
        let router = makeRouter(rules: StubRules(invalid: .unsupportedVersion))
        #expect(decide(exampleLink, profiles: [workProfile], router: router) == .open(LinkTarget(profile: workProfile.id)))
    }
}
