// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// A Space as the Link picker and the Link rules see it.
public struct SpaceChoice: Hashable, Identifiable, Sendable {
    public let id: SpaceID
    public let name: String
    public let emoji: String

    public init(id: SpaceID, name: String, emoji: String) {
        self.id = id
        self.name = name
        self.emoji = emoji
    }
}

/// Where a link opens: the Profile, a Space of it, and whether it must be a new Tab.
public struct LinkTarget: Hashable, Sendable {
    public let profile: ProfileID
    /// Nil opens it in the Profile's last active Space.
    public let space: SpaceID?
    /// Set by a Link rule. Without it, a Matching tab will be focused instead once those exist; today every link is a
    /// new Tab either way.
    public let forcesNewTab: Bool

    public init(profile: ProfileID, space: SpaceID? = nil, forcesNewTab: Bool = false) {
        self.profile = profile
        self.space = space
        self.forcesNewTab = forcesNewTab
    }
}

/// What to do with an incoming link.
public enum LinkDecision: Hashable, Sendable {
    /// Open it in the app that rewrote it.
    case openNative(NativeLink)
    /// Open it here without asking.
    case open(LinkTarget)
    /// Show the Link picker.
    case ask
}

/// Why a rule that matched a link was passed over. Never a guess: the next rule, or the Link picker, decides instead.
public enum LinkRuleProblem: Error, Hashable, Sendable {
    case unknownProfile
    case ambiguousProfile
    case unknownSpace
    case ambiguousSpace
}

/// Where the router reports what it could not use. The app writes these to the diagnostics and tells the user once.
@MainActor
public protocol LinkRoutingReporting: AnyObject {
    func rulesFileIsInvalid(_ error: LinkRulesError)
    /// The rule at `index` (from 0) matched the link but names a Profile or Space that cannot be found.
    func ruleWasSkipped(index: Int, because problem: LinkRuleProblem)
}

/// Decides where an incoming link goes, in this order: the installed app that can show it, the first Link rule that
/// matches and resolves, the only Profile, and last the Link picker. Matching tabs will decide before the Link picker
/// does, here.
@MainActor
public struct LinkRouter {
    private let rules: any LinkRulesProviding
    private let nativeApps: NativeAppLinks
    private let reporter: any LinkRoutingReporting

    public init(rules: any LinkRulesProviding, nativeApps: NativeAppLinks, reporter: any LinkRoutingReporting) {
        self.rules = rules
        self.nativeApps = nativeApps
        self.reporter = reporter
    }

    /// - Parameters:
    ///   - spacesOf: the Spaces of a Profile, asked only when a matching rule names a Space.
    ///   - includingNativeApps: false once the installed app refused the link.
    ///
    /// With a rules file that is invalid, no rule and no native app applies: the Link picker decides.
    public func decide(for link: IncomingLink, among profiles: [Profile], spacesOf: (ProfileID) -> [SpaceChoice],
                       includingNativeApps: Bool = true) -> LinkDecision {
        switch rules.load() {
        case .invalid(let error):
            reporter.rulesFileIsInvalid(error)
        case .rules(let set):
            if includingNativeApps, let native = nativeApps.link(for: link.url, enabled: set.enabledNativeApps) {
                return .openNative(native)
            }
            for (index, rule) in set.rules.enumerated()
            where rule.matches(link.url, openerBundleIdentifier: link.openerBundleIdentifier) {
                switch resolve(rule, among: profiles, spacesOf: spacesOf) {
                case .success(let target): return .open(target)
                case .failure(let problem): reporter.ruleWasSkipped(index: index, because: problem)
                }
            }
        }
        // With one Profile there is nothing to choose; with several, the user always chooses, and nothing is preselected.
        if profiles.count == 1, let only = profiles.first {
            return .open(LinkTarget(profile: only.id))
        }
        return .ask
    }

    private func resolve(_ rule: LinkRule, among profiles: [Profile],
                         spacesOf: (ProfileID) -> [SpaceChoice]) -> Result<LinkTarget, LinkRuleProblem> {
        let profile: Profile
        switch Self.resolve(rule.profile, among: profiles, id: { $0.id.rawValue }, name: { $0.name }) {
        case .found(let found): profile = found
        case .unknown: return .failure(.unknownProfile)
        case .ambiguous: return .failure(.ambiguousProfile)
        }
        guard let spaceReference = rule.space else {
            return .success(LinkTarget(profile: profile.id, forcesNewTab: rule.forcesNewTab))
        }
        switch Self.resolve(spaceReference, among: spacesOf(profile.id), id: { $0.id.rawValue }, name: { $0.name }) {
        case .found(let space):
            return .success(LinkTarget(profile: profile.id, space: space.id, forcesNewTab: rule.forcesNewTab))
        case .unknown: return .failure(.unknownSpace)
        case .ambiguous: return .failure(.ambiguousSpace)
        }
    }

    private enum Resolution<Item> {
        case found(Item), unknown, ambiguous
    }

    /// The identifier is tried first, then the exact name. A name two items share is not a match for either.
    private static func resolve<Item>(_ reference: String, among items: [Item], id: (Item) -> UUID,
                                      name: (Item) -> String) -> Resolution<Item> {
        if let uuid = UUID(uuidString: reference), let byID = items.first(where: { id($0) == uuid }) {
            return .found(byID)
        }
        let named = items.filter { name($0) == reference }
        switch named.count {
        case 0: return .unknown
        case 1: return .found(named[0])
        default: return .ambiguous
        }
    }
}
