// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// A link Safira received from another app.
public struct IncomingLink: Hashable, Sendable {
    public let url: URL
    /// Bundle identifier of the Opener, when macOS reports it.
    public let openerBundleIdentifier: String?

    public init(url: URL, openerBundleIdentifier: String? = nil) {
        self.url = url
        self.openerBundleIdentifier = openerBundleIdentifier
    }

    /// Only web links open in a Tab; other schemes (mailto:, slack:) hand off to another app.
    public var isWebLink: Bool {
        switch url.scheme?.lowercased() {
        case "http", "https": true
        default: false
        }
    }
}
