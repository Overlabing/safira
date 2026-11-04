// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// A link Safira received from another app.
public struct IncomingLink: Hashable, Sendable {
    public let url: URL
    /// Nil when macOS reports no sender, or one that is not an app.
    public let opener: Opener?

    public init(url: URL, opener: Opener? = nil) {
        self.url = url
        self.opener = opener
    }

    public var openerBundleIdentifier: String? { opener?.bundleIdentifier }

    /// Only web links open in a Tab; other schemes (mailto:, slack:) hand off to another app.
    public var isWebLink: Bool {
        switch url.scheme?.lowercased() {
        case "http", "https": true
        default: false
        }
    }

    /// A local file, such as an HTML page opened with Safira.
    public var isLocalFile: Bool {
        url.isFileURL
    }

    /// Safira registers for web links and local files; anything else that reaches it is dropped.
    public var isOpenable: Bool {
        isWebLink || isLocalFile
    }

    /// What the Link picker names the link by: the host of a web link, the file name of a local file.
    public var title: String {
        if isLocalFile { return url.lastPathComponent }
        return url.host(percentEncoded: false) ?? url.absoluteString
    }

    /// The text under the title: the whole address, or the path of a local file.
    public var detail: String {
        isLocalFile ? url.path(percentEncoded: false) : url.absoluteString
    }
}
