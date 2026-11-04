// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// A link rewritten to open in an installed app.
public struct NativeLink: Hashable, Sendable {
    public let app: NativeApp
    public let url: URL

    public init(app: NativeApp, url: URL) {
        self.app = app
        self.url = url
    }
}

/// The installed apps and the way to open a link in one: `NSWorkspace` in the app, literal answers in tests.
public protocol NativeApplications: Sendable {
    func isInstalled(bundleIdentifier: String) -> Bool
    /// True when the app accepted the link.
    func open(_ url: URL, bundleIdentifier: String) async -> Bool
}

/// The Slack team identifier of a workspace, which Slack's own link scheme needs.
public protocol SlackWorkspaceLookup: Sendable {
    /// Nil when it cannot be known: no folder was granted, or the workspace is not in it.
    func teamID(forDomain domain: String) -> String?
}

/// Rewrites web links of Slack, Linear, Notion and Figma into the links those apps open themselves. The formats come
/// from the apps' bundles: Linear and Figma map `<scheme>://<path>` onto their web origin, Notion swaps the scheme and
/// keeps the host, and Slack only takes `slack://channel?team=…&id=…`. Sign-in and OAuth pages stay in the browser, and
/// so does a link whose app is not installed.
public struct NativeAppLinks: Sendable {
    private let applications: any NativeApplications
    private let slack: any SlackWorkspaceLookup

    public init(applications: any NativeApplications, slack: any SlackWorkspaceLookup) {
        self.applications = applications
        self.slack = slack
    }

    public func link(for url: URL, enabled: Set<NativeApp>) -> NativeLink? {
        guard let rewritten = rewrite(url), enabled.contains(rewritten.app),
              applications.isInstalled(bundleIdentifier: rewritten.app.bundleIdentifier) else { return nil }
        return rewritten
    }

    private func rewrite(_ url: URL) -> NativeLink? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https" || components.scheme == "http",
              let host = components.host?.lowercased() else { return nil }
        let segments = components.percentEncodedPath.split(separator: "/").map(String.init)
        let first = segments.first ?? ""
        // Path, query and fragment as they came, appended to a new scheme and host.
        var rest = components.percentEncodedPath
        if let query = components.percentEncodedQuery { rest += "?" + query }
        if let fragment = components.percentEncodedFragment { rest += "#" + fragment }

        switch host {
        case "linear.app" where !first.isEmpty && !["login", "signup", "oauth", "api", "join"].contains(first):
            return NativeLink(app: .linear, string: "linear://" + rest.dropFirst())
        case "www.notion.so", "notion.so", "app.notion.com":
            guard !["", "login", "signup", "oauth", "oauth2", "install-integration", "api"].contains(first) else { return nil }
            return NativeLink(app: .notion, string: "notion://" + (host == "notion.so" ? "www.notion.so" : host) + rest)
        case "www.figma.com", "figma.com":
            guard ["design", "file", "proto", "board", "slides", "deck"].contains(first) else { return nil }
            return NativeLink(app: .figma, string: "figma://" + rest.dropFirst())
        case _ where host.hasSuffix(".slack.com") && first == "archives" && segments.count >= 2:
            return slackLink(domain: String(host.dropLast(".slack.com".count)), segments: segments, components: components)
        default:
            return nil
        }
    }

    private func slackLink(domain: String, segments: [String], components: URLComponents) -> NativeLink? {
        guard let team = slack.teamID(forDomain: domain) else { return nil }
        var parameters = [URLQueryItem(name: "team", value: team), URLQueryItem(name: "id", value: segments[1])]
        // /archives/C…/p1712345678123456 is the message 1712345678.123456; a thread reply adds thread_ts.
        if segments.count >= 3, segments[2].hasPrefix("p"), segments[2].count > 7 {
            let digits = segments[2].dropFirst()
            parameters.append(URLQueryItem(name: "message", value: digits.dropLast(6) + "." + digits.suffix(6)))
        }
        if let thread = components.queryItems?.first(where: { $0.name == "thread_ts" })?.value {
            parameters.append(URLQueryItem(name: "thread_ts", value: thread))
        }
        var slack = URLComponents()
        slack.scheme = "slack"
        slack.host = "channel"
        slack.queryItems = parameters
        return slack.string.flatMap { NativeLink(app: .slack, string: $0) }
    }
}

extension NativeLink {
    fileprivate init?(app: NativeApp, string: String) {
        guard let url = URL(string: string) else { return nil }
        self.init(app: app, url: url)
    }
}
