// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// A Link rule: a match on host, path and Opener that sends a link to a Profile, and optionally to a Space, without
/// asking.
public struct LinkRule: Hashable, Sendable {
    /// Lowercase; matches the host itself and its subdomains.
    public let host: String?
    /// Lowercase, with a leading slash and no trailing one; matches a leading run of whole path segments.
    public let path: String?
    /// The bundle identifier of the Opener.
    public let opener: String?
    /// The identifier or the exact name of the Profile.
    public let profile: String
    /// The identifier or the exact name of a Space of that Profile.
    public let space: String?
    /// Whether the link opens in a new Tab even when a Matching tab exists.
    public let forcesNewTab: Bool

    public init(host: String? = nil, path: String? = nil, opener: String? = nil, profile: String,
                space: String? = nil, forcesNewTab: Bool = false) {
        self.host = Self.clean(host)?.lowercased()
        self.path = Self.clean(path).map(Self.normalized(path:))
        self.opener = Self.clean(opener)
        self.profile = profile
        self.space = Self.clean(space)
        self.forcesNewTab = forcesNewTab
    }

    /// A rule with neither a host nor an Opener would send every link somewhere, so it is ignored.
    public var isActive: Bool {
        host != nil || opener != nil
    }

    /// True when every field the rule sets matches the link.
    public func matches(_ url: URL, openerBundleIdentifier: String?) -> Bool {
        guard isActive else { return false }
        if let host {
            guard let linkHost = url.host(percentEncoded: false)?.lowercased(),
                  linkHost == host || linkHost.hasSuffix("." + host) else { return false }
        }
        if let opener, opener != openerBundleIdentifier { return false }
        if let path {
            let linkPath = url.path(percentEncoded: false).lowercased()
            guard linkPath == path || linkPath.hasPrefix(path + "/") else { return false }
        }
        return true
    }

    private static func clean(_ field: String?) -> String? {
        guard let trimmed = field?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func normalized(path: String) -> String {
        var path = path.lowercased()
        if !path.hasPrefix("/") { path = "/" + path }
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }
}

/// The apps whose links open in the app itself when it is installed.
public enum NativeApp: String, CaseIterable, Hashable, Sendable {
    case slack, linear, notion, figma

    public var bundleIdentifier: String {
        switch self {
        case .slack: "com.tinyspeck.slackmacgap"
        case .linear: "com.linear"
        case .notion: "notion.id"
        case .figma: "com.figma.Desktop"
        }
    }
}

/// Everything the rules file holds.
public struct LinkRuleSet: Hashable, Sendable {
    /// In file order: the first rule that matches and resolves wins.
    public let rules: [LinkRule]
    public let enabledNativeApps: Set<NativeApp>

    public init(rules: [LinkRule] = [], enabledNativeApps: Set<NativeApp> = Set(NativeApp.allCases)) {
        self.rules = rules
        self.enabledNativeApps = enabledNativeApps
    }

    /// No rules and every native app on: what a Mac without a rules file gets.
    public static let empty = LinkRuleSet()
}

/// Why a rules file was refused. None of them holds a value from the file, only where the problem is.
public enum LinkRulesError: Error, Hashable, Sendable {
    /// The file exists but could not be read.
    case unreadable
    case notJSON
    /// `version` is missing or not 1.
    case unsupportedVersion
    /// A field is missing or has the wrong type; `location` is its path, for example `rules[2].profile`.
    case invalidField(location: String)

    public var explanation: String {
        switch self {
        case .unreadable: "The file could not be read."
        case .notJSON: "The file is not valid JSON."
        case .unsupportedVersion: "The file's \"version\" is missing or is not 1."
        case .invalidField(let location): "\"\(location)\" is missing or has the wrong type."
        }
    }
}

extension LinkRuleSet {
    /// Reads the rules file format of docs/architecture-v1.md §5.4. Unknown keys are ignored.
    public static func parse(_ data: Data) -> Result<LinkRuleSet, LinkRulesError> {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .failure(.notJSON) }
        guard let version = root["version"] as? Int, version == 1 else { return .failure(.unsupportedVersion) }
        do {
            guard let raw = root["rules"] as? [Any] else { throw LinkRulesError.invalidField(location: "rules") }
            let rules = try raw.enumerated().map { try rule(from: $1, location: "rules[\($0)]") }
            return .success(LinkRuleSet(rules: rules, enabledNativeApps: try nativeApps(from: root["nativeApps"])))
        } catch let error as LinkRulesError {
            return .failure(error)
        } catch {
            return .failure(.notJSON)
        }
    }

    private static func rule(from raw: Any, location: String) throws -> LinkRule {
        guard let fields = raw as? [String: Any] else { throw LinkRulesError.invalidField(location: location) }
        func text(_ key: String) throws -> String? {
            guard let value = fields[key] else { return nil }
            guard let text = value as? String else { throw LinkRulesError.invalidField(location: location + "." + key) }
            return text
        }
        guard let profile = try text("profile"), !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LinkRulesError.invalidField(location: location + ".profile")
        }
        var forcesNewTab = false
        if let value = fields["newTab"] {
            guard let flag = value as? Bool else { throw LinkRulesError.invalidField(location: location + ".newTab") }
            forcesNewTab = flag
        }
        return LinkRule(host: try text("host"), path: try text("path"), opener: try text("opener"), profile: profile,
                        space: try text("space"), forcesNewTab: forcesNewTab)
    }

    private static func nativeApps(from raw: Any?) throws -> Set<NativeApp> {
        guard let raw else { return Set(NativeApp.allCases) }
        guard let apps = raw as? [String: Any] else { throw LinkRulesError.invalidField(location: "nativeApps") }
        var enabled = Set(NativeApp.allCases)
        for (key, value) in apps {
            guard let app = NativeApp(rawValue: key) else { continue }
            guard let isOn = value as? Bool else { throw LinkRulesError.invalidField(location: "nativeApps." + key) }
            if !isOn { enabled.remove(app) }
        }
        return enabled
    }
}

/// What the rules file holds right now.
public enum LinkRulesLoad: Hashable, Sendable {
    case rules(LinkRuleSet)
    case invalid(LinkRulesError)
}

public protocol LinkRulesProviding: Sendable {
    func load() -> LinkRulesLoad
}

/// The rules file in the app's own container. It is read each time a link arrives, so an edit applies to the next
/// link. A missing file means no rules; an unreadable or invalid one is an error and no rule applies.
public struct LinkRulesFile: LinkRulesProviding {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> LinkRulesLoad {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .rules(.empty)
        } catch {
            return .invalid(.unreadable)
        }
        switch LinkRuleSet.parse(data) {
        case .success(let set): return .rules(set)
        case .failure(let error): return .invalid(error)
        }
    }
}
