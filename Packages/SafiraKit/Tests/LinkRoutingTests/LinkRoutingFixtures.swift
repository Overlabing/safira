// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import SafiraCore
import Synchronization

let devSpace = SpaceChoice(id: SpaceID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!, name: "Dev", emoji: "🛠")
let docsSpace = SpaceChoice(id: SpaceID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!, name: "Docs", emoji: "📄")
let readingSpace = SpaceChoice(id: SpaceID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!, name: "Reading", emoji: "📚")
let defaultSpaces: [ProfileID: [SpaceChoice]] = [workProfile.id: [devSpace, docsSpace], homeProfile.id: [readingSpace]]

@MainActor
final class RecordingDestination: LinkDestination {
    var profiles: [Profile]
    var spacesByProfile: [ProfileID: [SpaceChoice]]
    private(set) var opened: [(url: String, target: LinkTarget)] = []
    private(set) var focused: [(match: MatchingTab, link: String)] = []
    private(set) var lookups = 0
    private var shown: [(address: String, match: MatchingTab)] = []

    init(profiles: [Profile], spaces: [ProfileID: [SpaceChoice]] = defaultSpaces) {
        self.profiles = profiles
        spacesByProfile = spaces
    }

    func spaces(in profile: ProfileID) -> [SpaceChoice] {
        spacesByProfile[profile] ?? []
    }

    func open(_ url: URL, in target: LinkTarget) -> Bool {
        guard profiles.contains(where: { $0.id == target.profile }) else { return false }
        opened.append((url.absoluteString, target))
        return true
    }

    /// A Tab of `profile`, in `space`, that shows `address`.
    @discardableResult
    func showTab(_ address: String, in profile: Profile, space: SpaceChoice) -> MatchingTab {
        let match = MatchingTab(profile: profile.id, space: space.id, tab: TabID())
        shown.append((NormalizedAddress(URL(string: address)!)!.value, match))
        return match
    }

    func matchingTab(for address: NormalizedAddress, in profile: ProfileID) -> MatchingTab? {
        lookups += 1
        return shown.first { $0.match.profile == profile && $0.address == address.value }?.match
    }

    func focus(_ match: MatchingTab, openedFrom link: URL) -> Bool {
        guard shown.contains(where: { $0.match == match }) else { return false }
        focused.append((match, link.absoluteString))
        return true
    }
}

/// Holds each question open until the test answers it, so the order of events is under the test's control.
@MainActor
final class ScriptedChooser: ProfileChoosing {
    private(set) var asked: [IncomingLink] = []
    private(set) var offered: [[Profile]] = []
    private(set) var markedOpen: [Set<ProfileID>] = []
    private(set) var spacesAsked: [(profile: ProfileID, spaces: [SpaceChoice])] = []
    private var waiting: [CheckedContinuation<ProfileID?, Never>] = []
    private var waitingForSpace: [CheckedContinuation<SpaceID?, Never>] = []

    func chooseProfile(for link: IncomingLink, among profiles: [Profile], alreadyOpenIn: Set<ProfileID>) async -> ProfileID? {
        asked.append(link)
        offered.append(profiles)
        markedOpen.append(alreadyOpenIn)
        return await withCheckedContinuation { waiting.append($0) }
    }

    func chooseSpace(for link: IncomingLink, in profile: Profile, among spaces: [SpaceChoice]) async -> SpaceID? {
        spacesAsked.append((profile.id, spaces))
        return await withCheckedContinuation { waitingForSpace.append($0) }
    }

    func answer(_ choice: ProfileID?) {
        waiting.removeFirst().resume(returning: choice)
    }

    func answerSpace(_ choice: SpaceID?) {
        waitingForSpace.removeFirst().resume(returning: choice)
    }

    /// Lets the coordinator run until it asks, or until it has nothing left to do.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

struct StubRules: LinkRulesProviding {
    var result: LinkRulesLoad

    init(_ rules: [LinkRule] = [], nativeApps: Set<NativeApp> = Set(NativeApp.allCases)) {
        result = .rules(LinkRuleSet(rules: rules, enabledNativeApps: nativeApps))
    }

    init(invalid error: LinkRulesError) {
        result = .invalid(error)
    }

    func load() -> LinkRulesLoad { result }
}

/// Installed apps and the links they were asked to open.
final class StubApplications: NativeApplications {
    private let installed: Set<String>
    private let accepts: Bool
    private let log = Mutex<[(url: String, bundleIdentifier: String)]>([])

    init(installed: Set<NativeApp> = [], accepts: Bool = true) {
        self.installed = Set(installed.map(\.bundleIdentifier))
        self.accepts = accepts
    }

    var opened: [(url: String, bundleIdentifier: String)] { log.withLock { $0 } }

    func isInstalled(bundleIdentifier: String) -> Bool {
        installed.contains(bundleIdentifier)
    }

    func open(_ url: URL, bundleIdentifier: String) async -> Bool {
        log.withLock { $0.append((url.absoluteString, bundleIdentifier)) }
        return accepts
    }
}

struct StubSlack: SlackWorkspaceLookup {
    var teams: [String: String] = [:]

    func teamID(forDomain domain: String) -> String? { teams[domain] }
}

@MainActor
final class RecordingReporter: LinkRoutingReporting {
    private(set) var invalidFiles: [LinkRulesError] = []
    private(set) var skipped: [(index: Int, problem: LinkRuleProblem)] = []

    func rulesFileIsInvalid(_ error: LinkRulesError) { invalidFiles.append(error) }

    func ruleWasSkipped(index: Int, because problem: LinkRuleProblem) { skipped.append((index, problem)) }
}

@MainActor
func makeRouter(rules: StubRules = StubRules(), applications: StubApplications = StubApplications(),
                slack: StubSlack = StubSlack(), reporter: RecordingReporter = RecordingReporter(),
                matching: Bool = true) -> LinkRouter {
    LinkRouter(rules: rules, nativeApps: NativeAppLinks(applications: applications, slack: slack), reporter: reporter,
               isMatchingEnabled: { matching })
}

@MainActor
func makeCoordinator(_ destination: RecordingDestination, _ chooser: ScriptedChooser, rules: StubRules = StubRules(),
                     applications: StubApplications = StubApplications(), slack: StubSlack = StubSlack(),
                     reporter: RecordingReporter = RecordingReporter(), choiceLog: LinkChoiceLog? = nil,
                     asksForSpace: Bool = false, matching: Bool = true) -> ExternalLinkCoordinator {
    ExternalLinkCoordinator(
        destination: destination, chooser: chooser,
        router: makeRouter(rules: rules, applications: applications, slack: slack, reporter: reporter, matching: matching),
        nativeApplications: applications, choiceLog: choiceLog, asksForSpace: { asksForSpace })
}

func link(_ address: String, from opener: String? = nil) -> IncomingLink {
    IncomingLink(url: URL(string: address)!, opener: opener.map { Opener(bundleIdentifier: $0, name: nil) })
}
