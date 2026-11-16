// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// How a Profile answers the cookie consent prompts of the sites it visits. On by default: Safira rejects them.
public struct CookiePromptSettings: Hashable, Sendable, Codable {
    /// Safira answers "reject" for the user, or hides the prompt when it cannot reject.
    public var isRejecting: Bool
    /// The sites left alone, by host without a leading `www.`; a site's subdomains are left alone with it.
    public private(set) var exceptions: Set<String>

    public init(isRejecting: Bool = true, exceptions: Set<String> = []) {
        self.isRejecting = isRejecting
        self.exceptions = Set(exceptions.compactMap(Self.site(of:)))
    }

    /// Whether Safira answers the prompts of a page on this host.
    public func answers(onHost host: String?) -> Bool {
        guard isRejecting, let site = host.flatMap(Self.site(of:)) else { return false }
        return !isExcepted(site)
    }

    public func isExcepted(_ host: String) -> Bool {
        guard let site = Self.site(of: host) else { return false }
        var labels = site.split(separator: ".")
        while labels.count >= 1 {
            if exceptions.contains(labels.joined(separator: ".")) { return true }
            labels.removeFirst()
        }
        return false
    }

    public mutating func addException(forHost host: String) {
        if let site = Self.site(of: host) { exceptions.insert(site) }
    }

    public mutating func removeException(_ site: String) {
        exceptions.remove(site)
    }

    /// The lowercased host without a leading `www.`; nil when nothing is left.
    public static func site(of host: String) -> String? {
        var site = host.lowercased().trimmingCharacters(in: .whitespaces)
        if site.hasPrefix("www.") { site.removeFirst(4) }
        while site.hasSuffix(".") { site.removeLast() }
        return site.isEmpty ? nil : site
    }
}

/// What Safira did about the cookie prompt of the page a Tab shows. A new document starts with none.
public struct CookiePromptReport: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        /// The consent platform was found; Safira is answering it.
        case detected
        /// Safira answered "reject".
        case rejected
        /// No reject path: Safira hid the prompt.
        case hidden
        /// The platform was found but could not be answered.
        case failed
    }

    /// The page's host, without a leading `www.`.
    public var site: String
    /// The consent platform's name in autoconsent's rules (for example "Onetrust").
    public var platform: String
    public var outcome: Outcome

    public init(site: String, platform: String, outcome: Outcome) {
        self.site = site
        self.platform = platform
        self.outcome = outcome
    }

    /// Whether the address field shows it: once the prompt has been handled, or could not be.
    public var isShown: Bool { outcome != .detected }
}
