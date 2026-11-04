// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// What the text typed in the Command bar asks for: an address to open, or a search.
public enum CommandBarInput: Hashable, Sendable {
    case address(URL, scheme: AddressScheme)
    case search(String)

    /// Whether the user typed the scheme of an address or left Safira to choose it.
    public enum AddressScheme: Hashable, Sendable {
        case typed
        /// Typed without a scheme: Safira opened it over HTTPS and owes the user a warning before any HTTP load.
        case defaultedToHTTPS
    }

    /// Resolves typed text; nil when there is nothing to open. An address typed without a scheme gets `https://`.
    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let (url, scheme) = Self.webAddress(trimmed) {
            self = .address(url, scheme: scheme)
        } else {
            self = .search(trimmed)
        }
    }

    private static func webAddress(_ text: String) -> (URL, AddressScheme)? {
        guard !text.contains(where: \.isWhitespace) else { return nil }
        if text.contains("://") {
            guard let url = URL(string: text),
                  let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let host = url.host(), !host.isEmpty
            else { return nil }
            return (url, .typed)
        }
        let authority = text.prefix { !"/?#".contains($0) }
        guard !authority.contains("@"), isHostAndPort(authority) else { return nil }
        return URL(string: "https://\(text)").map { ($0, .defaultedToHTTPS) }
    }

    private static func isHostAndPort(_ authority: Substring) -> Bool {
        let parts = authority.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            guard (1...5).contains(parts[1].count), parts[1].allSatisfy(\.isASCII), parts[1].allSatisfy(\.isNumber)
            else { return false }
        }
        let host = parts[0].lowercased()
        return host == "localhost" || isIPv4(host) || isDomainName(host)
    }

    private static func isIPv4(_ host: String) -> Bool {
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { octet in
            octet.count <= 3 && octet.allSatisfy { $0.isASCII && $0.isNumber } && Int(octet).map { $0 <= 255 } == true
        }
    }

    /// A dotted name whose last label starts with a letter, so "3.14" stays a search.
    private static func isDomainName(_ host: String) -> Bool {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, let topLevel = labels.last, topLevel.count >= 2, topLevel.first?.isLetter == true
        else { return false }
        return labels.allSatisfy { label in
            !label.isEmpty && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}
