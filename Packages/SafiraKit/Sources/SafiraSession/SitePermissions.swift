// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore
import SafiraStore

/// What one Profile remembers about the sites that asked for the camera, the microphone or the location. A decision is
/// saved in the Profile's own database, so it never reaches another Profile, and it stays until the user revokes it.
@MainActor
@Observable
public final class SitePermissions {
    /// Every remembered decision, by site then capability.
    public private(set) var all: [SitePermission]
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

    public func revokeAll() {
        do {
            try database?.removeAllSitePermissions()
        } catch {
            onError("The site permissions could not be revoked", error)
            return
        }
        all = []
    }
}
