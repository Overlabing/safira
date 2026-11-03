// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// The only part of a page address a diagnostic line may carry. It is built from a URL's host and keeps nothing else:
/// no scheme, user, port, path, query or fragment, and no host the logger could not print as plain host characters.
public struct LoggedHost: Hashable, Sendable {
    public let name: String

    public init?(_ url: URL) {
        guard let host = url.host(percentEncoded: true)?.lowercased(), Self.isPlainHostName(host) else { return nil }
        name = host
    }

    private static let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-_:")

    private static func isPlainHostName(_ host: String) -> Bool {
        !host.isEmpty && host.count <= 253 && host.allSatisfy(allowed.contains)
    }
}
