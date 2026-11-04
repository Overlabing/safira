// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// How far back "Clear history and website data" reaches. Browsing data is otherwise kept until the user clears it
/// (decision D2), so there is no range for "automatically".
public enum ClearRange: String, CaseIterable, Sendable {
    case lastHour
    case lastDay
    case allTime

    /// The start of the range: everything from this moment until now goes. All time reaches back to `.distantPast`.
    public func start(now: Date = Date()) -> Date {
        switch self {
        case .lastHour: now.addingTimeInterval(-3_600)
        case .lastDay: now.addingTimeInterval(-86_400)
        case .allTime: .distantPast
        }
    }
}
