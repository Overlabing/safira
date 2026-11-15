// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// What Safira appends to WebKit's user agent: Safari's own `Version/<n> Safari/605.1.15`, so that sites that look
/// for Safari do not take Safira for an old or unknown browser. No Safira token: it would only make more sites sniff it
/// wrongly.
public enum SafariUserAgent {
    /// The token Safari has sent since WebKit froze its version number.
    public static let safariToken = "Safari/605.1.15"

    /// `Version/<safariVersion> Safari/605.1.15`. Without a readable Safari version, the macOS major version stands in
    /// for it: Safari's major version has followed the system's since macOS 26.
    public static func applicationName(safariVersion: String?, systemMajorVersion: Int) -> String {
        let version = safariVersion.flatMap(Self.validVersion) ?? "\(systemMajorVersion).0"
        return "Version/\(version) \(safariToken)"
    }

    /// The short version in the `Info.plist` of the Safari bundle at `url`, if there is one.
    public static func installedVersion(at url: URL) -> String? {
        Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The application name for this Mac, read once from the installed Safari.
    public static let current: String = applicationName(
        safariVersion: installedVersion(at: URL(filePath: "/Applications/Safari.app")),
        systemMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    )

    /// Digits and dots only, so that a damaged `Info.plist` cannot put anything else in the user agent.
    private static func validVersion(_ version: String) -> String? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
        else { return nil }
        return version
    }
}
