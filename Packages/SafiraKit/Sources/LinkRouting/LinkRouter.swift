// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore

/// What to do with an incoming link.
public enum LinkDecision: Hashable, Sendable {
    /// Open it in this Profile without asking.
    case open(ProfileID)
    /// Show the Link picker.
    case ask
}

/// Decides where an incoming link goes. Link rules and Matching tabs will decide before the Link picker does, here.
public enum LinkRouter {
    /// With one Profile there is nothing to choose; with several, the user always chooses, and nothing is preselected.
    public static func decide(for link: IncomingLink, among profiles: [Profile]) -> LinkDecision {
        if profiles.count == 1, let only = profiles.first {
            return .open(only.id)
        }
        return .ask
    }
}
