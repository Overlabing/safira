// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// Where an external link is delivered: the Profiles of the app and the place that opens a link in one of them.
@MainActor
public protocol LinkDestination: AnyObject {
    /// In sidebar order; never empty.
    var profiles: [Profile] { get }
    /// The Spaces of a Profile, in sidebar order. Asking may load the Profile, which the link is about to show anyway.
    func spaces(in profile: ProfileID) -> [SpaceChoice]
    /// Opens the link as a new Tab in the target's Space, or in the Profile's last active Space when it names none,
    /// and shows that Profile. False when the Profile or the Space no longer exists.
    @discardableResult
    func open(_ url: URL, in target: LinkTarget) -> Bool
    /// The Tab of the Profile, in any Space, that shows the address; a Tab not loaded since launch counts by its last
    /// saved address. Asking neither loads a page nor shows the Profile.
    func matchingTab(for address: NormalizedAddress, in profile: ProfileID) -> MatchingTab?
    /// Shows the Matching tab, switching Profile and Space as needed, with a banner offering to open `link` in a new
    /// Tab. False when the Tab no longer exists.
    @discardableResult
    func focus(_ match: MatchingTab, openedFrom link: URL) -> Bool
}

/// What the user chose in the Link picker, and whether they also asked for it to become a Link rule ("always").
public struct PickerAnswer<Choice: Hashable & Sendable>: Hashable, Sendable {
    public let choice: Choice
    public let remembers: Bool

    public init(_ choice: Choice, remembers: Bool = false) {
        self.choice = choice
        self.remembers = remembers
    }
}

/// Asks the user which Profile receives a link.
@MainActor
public protocol ProfileChoosing: AnyObject {
    /// Returns once the user has chosen, or nil when they dismissed the question. Nothing is preselected;
    /// `alreadyOpenIn` only marks the Profiles that have a Tab showing the link.
    func chooseProfile(for link: IncomingLink, among profiles: [Profile],
                       alreadyOpenIn: Set<ProfileID>) async -> PickerAnswer<ProfileID>?
    /// Returns once the user has chosen one of the Profile's Spaces, or nil when they dismissed the question.
    /// `remembering` is what "always" was set to in the Profile step.
    func chooseSpace(for link: IncomingLink, in profile: Profile, among spaces: [SpaceChoice],
                     remembering: Bool) async -> PickerAnswer<SpaceID>?
}

/// Where a choice the user asked to keep becomes a Link rule. A failure is the implementation's to tell the user.
@MainActor
public protocol LinkRuleRemembering: AnyObject {
    /// Adds a rule that sends links from `host` to the Profile, and to the Space when one was chosen.
    func rememberChoice(host: String, profile: ProfileID, space: SpaceID?)
}

/// Takes the links other apps send and delivers them one at a time: a link that arrives while the Link picker is
/// open waits its turn.
@MainActor
public final class ExternalLinkCoordinator {
    private let destination: any LinkDestination
    private let chooser: any ProfileChoosing
    private let router: LinkRouter
    private let nativeApplications: any NativeApplications
    private let choiceLog: LinkChoiceLog?
    private let rememberer: (any LinkRuleRemembering)?
    private let asksForSpace: @MainActor () -> Bool
    private var pending: [IncomingLink] = []
    private var draining: Task<Void, Never>?

    /// - Parameter asksForSpace: whether the Link picker asks for the Space after the Profile; read for each link.
    public init(destination: any LinkDestination, chooser: any ProfileChoosing, router: LinkRouter,
                nativeApplications: any NativeApplications, choiceLog: LinkChoiceLog? = nil,
                rememberer: (any LinkRuleRemembering)? = nil, asksForSpace: @escaping @MainActor () -> Bool = { false }) {
        self.destination = destination
        self.chooser = chooser
        self.router = router
        self.nativeApplications = nativeApplications
        self.choiceLog = choiceLog
        self.rememberer = rememberer
        self.asksForSpace = asksForSpace
    }

    public func receive(_ link: IncomingLink) {
        guard link.isOpenable else { return }
        pending.append(link)
        guard draining == nil else { return }
        draining = Task { await drain() }
    }

    /// Returns when every link received so far has been delivered or dismissed.
    public func waitUntilIdle() async {
        await draining?.value
    }

    private func drain() async {
        while !pending.isEmpty {
            await deliver(pending.removeFirst())
        }
        draining = nil
    }

    /// Where `link` would go right now, by the very decision `deliver` makes, but without reporting an invalid rules file
    /// and without waiting for an installed app: for the Link rules window's "Where would this link go?".
    public func route(for link: IncomingLink) -> LinkRoute {
        route(for: link, using: router.withoutReporting())
    }

    private func route(for link: IncomingLink, using router: LinkRouter, includingNativeApps: Bool = true) -> LinkRoute {
        let destination = destination
        return router.route(for: link, among: destination.profiles, spacesOf: { destination.spaces(in: $0) },
                            matchingTab: { destination.matchingTab(for: $1, in: $0) },
                            includingNativeApps: includingNativeApps)
    }

    private func deliver(_ link: IncomingLink) async {
        let profiles = destination.profiles
        let destination = destination
        let matchingTab: MatchingTabLookup = { destination.matchingTab(for: $1, in: $0) }
        var decision = route(for: link, using: router).decision
        if case .openNative(let native) = decision {
            if await nativeApplications.open(native.url, bundleIdentifier: native.app.bundleIdentifier) { return }
            decision = route(for: link, using: router, includingNativeApps: false).decision
        }
        switch decision {
        case .open(let target):
            destination.open(link.url, in: target)
        case .focus(let match):
            destination.focus(match, openedFrom: link.url)
        case .ask, .openNative:  // `includingNativeApps: false` never yields .openNative
            guard let answer = await askTarget(for: link, among: profiles, matchingTab: matchingTab) else { return }
            let target = answer.choice
            let delivered = if let match = router.matchingTab(for: link, in: target, lookup: matchingTab) {
                destination.focus(match, openedFrom: link.url)
            } else {
                destination.open(link.url, in: target)
            }
            guard delivered else { return }
            choiceLog?.record(link.url, chosen: target.profile)
            if answer.remembers, let host = link.rememberableHost {
                rememberer?.rememberChoice(host: host, profile: target.profile, space: target.space)
            }
        }
    }

    private func askTarget(for link: IncomingLink, among profiles: [Profile],
                           matchingTab: MatchingTabLookup) async -> PickerAnswer<LinkTarget>? {
        let alreadyOpen = router.profilesShowing(link, among: profiles, lookup: matchingTab)
        guard let answer = await chooser.chooseProfile(for: link, among: profiles, alreadyOpenIn: alreadyOpen) else { return nil }
        let id = answer.choice
        guard asksForSpace(), let profile = profiles.first(where: { $0.id == id }) else {
            return PickerAnswer(LinkTarget(profile: id), remembers: answer.remembers)
        }
        let spaces = destination.spaces(in: id)
        // A Profile with one Space has nothing to choose.
        guard spaces.count > 1 else { return PickerAnswer(LinkTarget(profile: id), remembers: answer.remembers) }
        guard let spaceAnswer = await chooser.chooseSpace(for: link, in: profile, among: spaces,
                                                          remembering: answer.remembers) else { return nil }
        return PickerAnswer(LinkTarget(profile: id, space: spaceAnswer.choice), remembers: spaceAnswer.remembers)
    }
}
