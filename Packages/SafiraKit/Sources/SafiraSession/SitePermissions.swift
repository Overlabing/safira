// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore
import SafiraStore

/// What one Profile remembers about the sites that asked for the camera, the microphone or the location, and about the
/// apps links may open (by scheme, whatever the site). A decision is saved in the Profile's own database, so it never
/// reaches another Profile, and it stays until the user revokes it.
@MainActor
@Observable
public final class SitePermissions {
    /// Every remembered decision, by site then capability.
    public private(set) var all: [SitePermission]
    /// Every remembered choice about opening an app, by scheme.
    public private(set) var appLinks: [AppLinkChoice]
    @ObservationIgnored private let database: ProfileDatabase?
    @ObservationIgnored private let onError: @MainActor (String, any Error) -> Void

    /// - Parameter database: where decisions are kept; nil keeps them for this run only.
    public init(database: ProfileDatabase? = nil,
                onError: @escaping @MainActor (String, any Error) -> Void = { _, _ in }) {
        self.database = database
        self.onError = onError
        do {
            all = try database?.sitePermissions() ?? []
        } catch {
            all = []
            onError("The remembered site permissions could not be read", error)
        }
        do {
            appLinks = try database?.appLinkChoices() ?? []
        } catch {
            appLinks = []
            onError("The remembered app choices could not be read", error)
        }
    }

    public func decision(for kind: PermissionKind, at origin: SiteOrigin) -> PermissionDecision? {
        all.first { $0.origin == origin && $0.kind == kind }?.decision
    }

    public func verdict(requesting kinds: [PermissionKind], at origin: SiteOrigin) -> PermissionVerdict {
        PermissionRule.verdict(requesting: kinds) { decision(for: $0, at: origin) }
    }

    /// Remembers one decision for every capability named. A decision that could not be saved is not remembered, so the
    /// user is asked again rather than trusting something the next launch would forget.
    public func remember(_ decision: PermissionDecision, for kinds: [PermissionKind], at origin: SiteOrigin,
                         now: Date = Date()) {
        for kind in kinds {
            let permission = SitePermission(origin: origin, kind: kind, decision: decision, decidedAt: now)
            do {
                try database?.save(permission)
            } catch {
                onError("The site permission could not be saved", error)
                continue
            }
            all.removeAll { $0.origin == origin && $0.kind == kind }
            all.append(permission)
        }
        all.sort { ($0.origin, $0.kind.rawValue) < ($1.origin, $1.kind.rawValue) }
    }

    /// Forgets a decision: the site is asked about again the next time it requests the capability.
    public func revoke(_ kind: PermissionKind, at origin: SiteOrigin) {
        do {
            try database?.removeSitePermission(origin: origin, kind: kind)
        } catch {
            onError("The site permission could not be revoked", error)
            return
        }
        all.removeAll { $0.origin == origin && $0.kind == kind }
    }

    /// Forgets every site permission and every app choice.
    public func revokeAll() {
        do {
            try database?.removeAllSitePermissions()
        } catch {
            onError("The site permissions could not be revoked", error)
            return
        }
        all = []
        appLinks = []
    }

    public func appLinkDecision(for scheme: URLScheme) -> PermissionDecision? {
        appLinks.first { $0.scheme == scheme }?.decision
    }

    /// Remembers whether links of `scheme` may open their app. A choice that could not be saved is not remembered, so
    /// the user is asked again rather than trusting something the next launch would forget.
    public func rememberAppLink(_ decision: PermissionDecision, for scheme: URLScheme, now: Date = Date()) {
        let choice = AppLinkChoice(scheme: scheme, decision: decision, decidedAt: now)
        do {
            try database?.save(choice)
        } catch {
            onError("The app choice could not be saved", error)
            return
        }
        appLinks.removeAll { $0.scheme == scheme }
        appLinks.append(choice)
        appLinks.sort { $0.scheme < $1.scheme }
    }

    /// Forgets the choice for a scheme: its links ask again.
    public func revokeAppLink(_ scheme: URLScheme) {
        do {
            try database?.removeAppLinkChoice(for: scheme)
        } catch {
            onError("The app choice could not be revoked", error)
            return
        }
        appLinks.removeAll { $0.scheme == scheme }
    }
}
