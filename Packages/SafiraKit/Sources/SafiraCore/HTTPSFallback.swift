// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// A top-level navigation that failed before any content arrived, as WebKit reports it.
public struct LoadFailure: Hashable, Sendable {
    public var url: URL
    public var domain: String
    public var code: Int

    public init(url: URL, domain: String, code: Int) {
        self.url = url
        self.domain = domain
        self.code = code
    }
}

/// What the user must be told before Safira loads an address over HTTP.
public struct InsecureConnectionWarning: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// Nothing answered over TLS: the port is closed, the connection dropped or timed out, or the server is not
        /// speaking TLS.
        case noSecureConnection
        /// The server speaks TLS but its certificate does not verify.
        case invalidCertificate
    }

    /// The address that could not be opened securely.
    public var failedURL: URL
    /// The same address over HTTP, loaded only if the user asks for it.
    public var httpURL: URL
    public var reason: Reason

    public var host: String { failedURL.host() ?? "" }

    public init(failedURL: URL, httpURL: URL, reason: Reason) {
        self.failedURL = failedURL
        self.httpURL = httpURL
        self.reason = reason
    }
}

/// The HTTPS-first rule: an address typed without a scheme is tried over HTTPS; when the site offers no secure
/// connection, the user is warned before any HTTP load.
public enum HTTPSFallback {
    /// The warning to show after `failure`, or nil when HTTP must not be offered.
    ///
    /// It mirrors what WebKit itself offers for an HTTPS-first navigation (spike S6): every failure of the secure
    /// connection, certificate failures included, and none that HTTP would not cure, such as an unknown host.
    public static func warning(after failure: LoadFailure) -> InsecureConnectionWarning? {
        guard failure.url.scheme?.lowercased() == "https", failure.domain == NSURLErrorDomain,
              let reason = reason(URLError.Code(rawValue: failure.code)),
              let httpURL = httpURL(for: failure.url)
        else { return nil }
        return InsecureConnectionWarning(failedURL: failure.url, httpURL: httpURL, reason: reason)
    }

    /// Whether two addresses are the same navigation target. WebKit reports "https://host" as "https://host/".
    public static func isSameAddress(_ first: URL, _ second: URL) -> Bool {
        func normalized(_ url: URL) -> URLComponents? {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            if components.path.isEmpty { components.path = "/" }
            components.fragment = nil
            return components
        }
        return normalized(first) == normalized(second)
    }

    private static func reason(_ code: URLError.Code) -> InsecureConnectionWarning.Reason? {
        switch code {
        case .secureConnectionFailed, .cannotConnectToHost, .timedOut, .networkConnectionLost:
            .noSecureConnection
        case .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            .invalidCertificate
        default:
            nil
        }
    }

    /// The default HTTPS port has no meaning over HTTP, so it is dropped; any other port is kept.
    private static func httpURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "http"
        if components.port == 443 { components.port = nil }
        return components.url
    }
}
