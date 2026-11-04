// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// Where an external link is delivered: the Profiles of the app and the place that opens a link in one of them.
@MainActor
public protocol LinkDestination: AnyObject {
    /// In sidebar order; never empty.
    var profiles: [Profile] { get }
    /// Opens the link as a new Tab in the Profile's last active Space and shows that Profile. False when the Profile
    /// no longer exists.
    @discardableResult
    func open(_ url: URL, in profile: ProfileID) -> Bool
}

/// Asks the user which Profile receives a link.
@MainActor
public protocol ProfileChoosing: AnyObject {
    /// Returns once the user has chosen, or nil when they dismissed the question. Nothing is preselected.
    func chooseProfile(for link: IncomingLink, among profiles: [Profile]) async -> ProfileID?
}

/// Takes the links other apps send and delivers them one at a time: a link that arrives while the Link picker is
/// open waits its turn.
@MainActor
public final class ExternalLinkCoordinator {
    private let destination: any LinkDestination
    private let chooser: any ProfileChoosing
    private let choiceLog: LinkChoiceLog?
    private var pending: [IncomingLink] = []
    private var draining: Task<Void, Never>?

    public init(destination: any LinkDestination, chooser: any ProfileChoosing, choiceLog: LinkChoiceLog? = nil) {
        self.destination = destination
        self.chooser = chooser
        self.choiceLog = choiceLog
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

    private func deliver(_ link: IncomingLink) async {
        let profiles = destination.profiles
        switch LinkRouter.decide(for: link, among: profiles) {
        case .open(let profile):
            destination.open(link.url, in: profile)
        case .ask:
            guard let profile = await chooser.chooseProfile(for: link, among: profiles),
                  destination.open(link.url, in: profile) else { return }
            choiceLog?.record(link.url, chosen: profile)
        }
    }
}
