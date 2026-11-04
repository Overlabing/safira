// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// The scheme of a link, in lower case: `mailto`, `slack`, `zoommtg`. Letter case never distinguishes two schemes.
public struct URLScheme: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let rawValue: String

    /// Nil unless `string` is a scheme as RFC 3986 writes it: a letter, then letters, digits, `+`, `-` or `.`.
    public init?(_ string: String) {
        let lowered = string.lowercased()
        guard let first = lowered.unicodeScalars.first, ("a"..."z").contains(first),
              lowered.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || "+-.".unicodeScalars.contains($0) })
        else { return nil }
        rawValue = lowered
    }

    public var description: String { rawValue }

    public static func < (lhs: URLScheme, rhs: URLScheme) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A link a page followed that the web engine cannot show, so that only another app could take it. The page asked for
/// it; nothing has been opened.
public struct NonWebLink: Hashable, Sendable {
    public let url: URL
    public let scheme: URLScheme

    /// Nil when `url` has no scheme.
    public init?(_ url: URL) {
        guard let scheme = url.scheme.flatMap(URLScheme.init) else { return nil }
        self.url = url
        self.scheme = scheme
    }
}

/// The app the system would hand a link to, as the confirmation names it.
public struct ExternalApp: Hashable, Sendable {
    public let name: String
    /// Where the app is, so that the link opens in the app the user was told about and not in another one.
    public let location: URL

    public init(name: String, location: URL) {
        self.name = name
        self.location = location
    }
}

/// A question for the user: this page, in this Profile, wants to open this app.
public struct AppLinkPrompt: Hashable, Sendable {
    public let profileID: ProfileID
    public let scheme: URLScheme
    public let app: ExternalApp
    /// The host of the page that asked; nil for a page without one, such as a local file.
    public let requestedBy: String?

    public init(profileID: ProfileID, scheme: URLScheme, app: ExternalApp, requestedBy: String?) {
        self.profileID = profileID
        self.scheme = scheme
        self.app = app
        self.requestedBy = requestedBy
    }
}

/// Nothing opened, because no app on this Mac takes the scheme.
public struct AppLinkRefusal: Hashable, Sendable {
    public let profileID: ProfileID
    public let scheme: URLScheme
    public let requestedBy: String?

    public init(profileID: ProfileID, scheme: URLScheme, requestedBy: String?) {
        self.profileID = profileID
        self.scheme = scheme
        self.requestedBy = requestedBy
    }
}

/// The choice a Profile remembers for one scheme: links of that scheme may open their app without asking, or never do.
public struct AppLinkChoice: Hashable, Sendable, Identifiable {
    public let scheme: URLScheme
    public let decision: PermissionDecision
    public let decidedAt: Date

    public init(scheme: URLScheme, decision: PermissionDecision, decidedAt: Date) {
        self.scheme = scheme
        self.decision = decision
        self.decidedAt = decidedAt
    }

    public var id: String { scheme.rawValue }
}

/// What came of a non-web link.
public enum AppLinkOutcome: Hashable, Sendable {
    case opened(ExternalApp)
    /// The user said no, now or when they chose to remember it.
    case declined
    /// No app takes the scheme: the user was told, and nothing opened.
    case noApp
    /// The app was chosen but the system could not open the link in it.
    case failed
    /// Nothing was asked and nothing opened: the same scheme was already waiting for an answer in this Profile, or
    /// nobody was there to ask.
    case ignored
}
