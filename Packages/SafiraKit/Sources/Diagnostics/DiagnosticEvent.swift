// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import OSLog

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

    public enum Level: String, Sendable {
        case info, notice, error

        var osLogType: OSLogType {
            switch self {
            case .info: .info
            case .notice: .default
            case .error: .error
            }
        }
    }

    public var level: Level {
        switch self {
        case .tabCounts, .memory: .info
        case .pageLoaded, .debugMode, .linkRuleSkipped: .notice
        case .linkRulesInvalid: .error
        // A navigation the user or the page itself replaced is expected, not a failure.
        case .loadFailed(_, let error): error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled ? .notice : .error
        }
    }

    /// Whether the line tells where the user browsed or how long a page took. A failure without a host does not.
    public var carriesSiteInformation: Bool {
        switch self {
        case .pageLoaded: true
        case .loadFailed(let host, _): host != nil
        case .tabCounts, .memory, .debugMode, .linkRuleSkipped, .linkRulesInvalid: false
        }
    }

    /// The text of the line after its timestamp and level.
    public var message: String {
        switch self {
        case .pageLoaded(let host, let milliseconds):
            "page-loaded host=\(host?.name ?? "-") ms=\(milliseconds)"
        case .loadFailed(let host, let error):
            "load-failed host=\(host?.name ?? "-") domain=\(error.domain) code=\(error.code)"
        case .tabCounts(let counts):
            "tabs blank=\(counts.blank) loading=\(counts.loading) loaded=\(counts.loaded)"
        case .memory(let bytes):
            "memory footprint-bytes=\(bytes)"
        case .debugMode(let isOn):
            "debug-mode \(isOn ? "on" : "off")"
        case .linkRuleSkipped(let index, let reason):
            "link-rule-skipped index=\(index) reason=\(reason.rawValue)"
        case .linkRulesInvalid(let problem):
            "link-rules-invalid problem=\(problem.rawValue)"
        }
    }
}
