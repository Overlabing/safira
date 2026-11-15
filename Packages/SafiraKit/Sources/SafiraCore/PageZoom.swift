// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// How large a page is drawn: one of Safari's zoom steps, 100% being the page's own size.
public struct PageZoom: Hashable, Sendable {
    /// Safari's steps, smallest first.
    public static let levels: [Double] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2, 2.5, 3]
    public static let actualSize = PageZoom(factor: 1)

    public let factor: Double

    /// A factor between two steps, as a newer build may have saved, snaps to the nearest step.
    public init(factor: Double) {
        self.factor = Self.levels.min { abs($0 - factor) < abs($1 - factor) } ?? 1
    }

    public var isActualSize: Bool { factor == 1 }

    /// The next step up; nil at the largest.
    public var zoomedIn: PageZoom? {
        Self.levels.first { $0 > factor }.map(PageZoom.init(factor:))
    }

    /// The next step down; nil at the smallest.
    public var zoomedOut: PageZoom? {
        Self.levels.last { $0 < factor }.map(PageZoom.init(factor:))
    }

    /// The badge's text, "125%".
    public var percentage: String {
        "\(Int((factor * 100).rounded()))%"
    }
}

/// The site a zoom is remembered for: the host of a web address, letter case ignored. Every page of the host shares it,
/// whatever its scheme, port or path, as in Safari.
public struct ZoomSite: Hashable, Sendable, Comparable {
    public let host: String

    /// Nil for an address with no host, or one that is not a web page (`file:`, `about:`).
    public init?(_ url: URL?) {
        guard let url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        self.host = host
    }

    /// Reads back a stored host.
    public init?(host: String) {
        let host = host.lowercased()
        guard !host.isEmpty else { return nil }
        self.host = host
    }

    public static func < (lhs: ZoomSite, rhs: ZoomSite) -> Bool {
        lhs.host < rhs.host
    }
}
