// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DiagnosticsKit
import Foundation

/// How an error is written: its domain and code, never its description, which can quote an address or a title.
public struct ErrorSummary: Hashable, Sendable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        let plain = domain.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-") }
        self.domain = plain.isEmpty ? "unknown" : String(plain.prefix(64))
        self.code = code
    }

    public init(_ error: any Error) {
        let error = error as NSError
        self.init(domain: error.domain, code: error.code)
    }
}

/// How many open Tabs are in each state.
public struct TabCounts: Hashable, Sendable {
    /// Tabs with no address yet.
    public var blank: Int
    public var loading: Int
    public var loaded: Int

    public init(blank: Int = 0, loading: Int = 0, loaded: Int = 0) {
        self.blank = blank
        self.loading = loading
        self.loaded = loaded
    }
}

/// Why a Link rule that matched a link was passed over.
public enum LinkRuleSkipReason: String, Hashable, Sendable {
    case unknownProfile, ambiguousProfile, unknownSpace, ambiguousSpace
}

/// Why the Link rules file was refused.
public enum LinkRulesFileProblem: String, Hashable, Sendable {
    case unreadable, notJSON, unsupportedVersion, invalidField
}

/// Everything Debug mode may record. Each case carries typed fields only, so a line cannot hold a path, a query, a
/// title, a cookie or a Space or Profile name.
public enum DiagnosticEvent: Hashable, Sendable {
    /// A page finished loading, `milliseconds` after it committed.
    case pageLoaded(host: LoggedHost?, milliseconds: Int)
    case loadFailed(host: LoggedHost?, error: ErrorSummary)
    case tabCounts(TabCounts)
    case memory(footprintBytes: UInt64)
    case debugMode(isOn: Bool)
    /// The rule at `index` (from 0) matched a link but names a Profile or Space that cannot be found, so it was not used.
    case linkRuleSkipped(index: Int, reason: LinkRuleSkipReason)
    /// The Link rules file is invalid, so no rule applied.
    case linkRulesInvalid(LinkRulesFileProblem)
}

extension DiagnosticEvent: DiagnosticEventConvertible {
    public var category: String {
        switch self {
        case .pageLoaded, .loadFailed: "navigation"
        case .tabCounts, .memory: "sample"
        case .debugMode: "app"
        case .linkRuleSkipped, .linkRulesInvalid: "links"
        }
    }

    public var level: DiagnosticLevel {
        switch self {
        // Notice is the lowest level the file keeps.
        case .tabCounts, .memory, .pageLoaded, .debugMode, .linkRuleSkipped: .notice
        case .linkRulesInvalid: .error
        // A navigation the user or the page itself replaced is expected, not a failure.
        case .loadFailed(_, let error): error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled ? .notice : .error
        }
    }

    /// A host is a private value, and so is a page timing, which tells where the user browsed even without its host:
    /// under `OSLogPolicy.publicMessagesAlways` such a line reaches the system log only while Debug mode is on, and the
    /// file reads `<private>` in its place. Every other value is public, so its line always reaches the system log.
    public var message: DiagnosticMessage {
        switch self {
        case .pageLoaded(let host, let milliseconds):
            "page-loaded host=\(host?.name ?? "-", privacy: .private) ms=\(milliseconds)"
        case .loadFailed(let host?, let error):
            "load-failed host=\(host.name, privacy: .private) domain=\(error.domain, privacy: .public) code=\(error.code)"
        case .loadFailed(nil, let error):
            "load-failed host=- domain=\(error.domain, privacy: .public) code=\(error.code)"
        case .tabCounts(let counts):
            "tabs blank=\(counts.blank) loading=\(counts.loading) loaded=\(counts.loaded)"
        case .memory(let bytes):
            "memory footprint-bytes=\(bytes)"
        case .debugMode(let isOn):
            "debug-mode \(isOn ? "on" : "off", privacy: .public)"
        case .linkRuleSkipped(let index, let reason):
            "link-rule-skipped index=\(index) reason=\(reason.rawValue, privacy: .public)"
        case .linkRulesInvalid(let problem):
            "link-rules-invalid problem=\(problem.rawValue, privacy: .public)"
        }
    }
}
