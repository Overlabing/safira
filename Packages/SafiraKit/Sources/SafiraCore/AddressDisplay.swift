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
}
