// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// How an address is worded where space is short: the sidebar's address pill shows the host only, a suggestion row
/// shows the host and path after the page's title. The full address is always what hover and VoiceOver give.
public struct AddressDisplay: Equatable, Sendable {
    public let address: URL

    public init(_ address: URL) {
        self.address = address
    }

    /// The host, or the whole address for one without a host (a file, `about:blank`).
    public var host: String {
        address.host() ?? address.absoluteString
    }

    /// The host followed by the path, without the scheme, the query, the fragment or a lone trailing slash.
    public var hostAndPath: String {
        guard let host = address.host() else { return address.absoluteString }
        let path = address.path(percentEncoded: false)
        return path == "/" ? host : host + path
    }

    /// A page sent in the clear over plain HTTP: the pill marks it. An encrypted page has no mark, nor has one that is
    /// not on the network (a file, `about:blank`), nor a loopback host, which browsers count as a secure context
    /// (`localhost`, `*.localhost`, 127.0.0.0/8, `::1`).
    public var isNotSecure: Bool {
        address.scheme?.lowercased() == "http" && !isLoopback
    }

    /// An http or https address: what can be copied as a web link, unlike a file's.
    public var isWebAddress: Bool {
        ["http", "https"].contains(address.scheme?.lowercased())
    }

    private var isLoopback: Bool {
        guard var host = address.host(percentEncoded: false)?.lowercased() else { return false }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1" { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.first == "127" && octets.allSatisfy { UInt8($0) != nil }
    }
}
