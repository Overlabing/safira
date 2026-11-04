// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// A device capability a site can ask for.
public enum PermissionKind: String, CaseIterable, Hashable, Sendable {
    case camera
    case microphone
    case location
}

/// What the user decided about a request; a decision is remembered only when the user asks for it.
public enum PermissionDecision: String, Hashable, Sendable {
    case allow
    case deny
}

/// The site a decision applies to: scheme, host and port, as WebKit names a security origin. A decision for
/// `https://example.com` says nothing about `http://example.com` or `https://example.com:8443`.
public struct SiteOrigin: Hashable, Sendable, Comparable {
    public let scheme: String
    public let host: String
    /// Nil for the scheme's default port.
    public let port: Int?

    /// Nil without a scheme or a host. Letter case does not matter; a port of 0 or less is the default port.
    public init?(scheme: String, host: String, port: Int? = nil) {
        let scheme = scheme.lowercased()
        // An IPv6 host is written with or without its brackets depending on who reports it.
        let host = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !scheme.isEmpty, !host.isEmpty else { return nil }
        self.scheme = scheme
        self.host = host
        self.port = port.flatMap { $0 > 0 ? $0 : nil }
    }

    /// Reads back what `identifier` wrote.
    public init?(identifier: String) {
        guard let components = URLComponents(string: identifier), let scheme = components.scheme,
              let host = components.host else { return nil }
        self.init(scheme: scheme, host: host, port: components.port)
    }

    /// The stored form, for example `https://example.com:8443`.
    public var identifier: String {
        let host = host.contains(":") ? "[\(host)]" : host
        return "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "")
    }

    public static func < (lhs: SiteOrigin, rhs: SiteOrigin) -> Bool {
        lhs.identifier < rhs.identifier
    }
}

/// One remembered decision: this site may, or may not, use this capability in this Profile.
public struct SitePermission: Hashable, Sendable, Identifiable {
    public let origin: SiteOrigin
    public let kind: PermissionKind
    public let decision: PermissionDecision
    public let decidedAt: Date

    public init(origin: SiteOrigin, kind: PermissionKind, decision: PermissionDecision, decidedAt: Date) {
        self.origin = origin
        self.kind = kind
        self.decision = decision
        self.decidedAt = decidedAt
    }

    public var id: String { "\(origin.identifier) \(kind.rawValue)" }
}

/// What to do with a request, given what the Profile remembers.
public enum PermissionVerdict: Hashable, Sendable {
    case allow
    case deny
    /// Ask the user about these capabilities; the others were already allowed.
    case ask([PermissionKind])
}

public enum PermissionRule {
    /// A remembered denial refuses the whole request without asking again; a request is allowed without asking only
    /// when every capability it names is remembered as allowed; otherwise the user is asked about the capabilities
    /// the Profile has no decision for. Nothing is allowed by default, and a request for nothing is denied.
    public static func verdict(requesting kinds: [PermissionKind],
                               remembered: (PermissionKind) -> PermissionDecision?) -> PermissionVerdict {
        guard !kinds.isEmpty else { return .deny }
        let decisions = kinds.map { ($0, remembered($0)) }
        if decisions.contains(where: { $0.1 == .deny }) { return .deny }
        let unknown = decisions.filter { $0.1 == nil }.map(\.0)
        return unknown.isEmpty ? .allow : .ask(unknown)
    }
}

/// A question for the user: this site, in this Profile, wants these capabilities.
public struct PermissionPrompt: Hashable, Sendable {
    public let profileID: ProfileID
    public let origin: SiteOrigin
    public let kinds: [PermissionKind]

    public init(profileID: ProfileID, origin: SiteOrigin, kinds: [PermissionKind]) {
        self.profileID = profileID
        self.origin = origin
        self.kinds = kinds
    }
}

public struct PermissionAnswer: Hashable, Sendable {
    public let decision: PermissionDecision
    /// Keep the decision for this site in this Profile, so that it is not asked again until the user revokes it.
    public let remember: Bool

    public init(decision: PermissionDecision, remember: Bool) {
        self.decision = decision
        self.remember = remember
    }
}
