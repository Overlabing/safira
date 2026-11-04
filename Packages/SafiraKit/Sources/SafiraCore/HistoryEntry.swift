// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// A page a Profile visited, with the title it last had. A page that holds a password field or was reached by a POST
/// request is kept by its address only (decision D1), so its title is nil.
public struct HistoryEntry: Hashable, Sendable {
    public let url: URL
    public let title: String?

    public init(url: URL, title: String?) {
        self.url = url
        self.title = title
    }
}
