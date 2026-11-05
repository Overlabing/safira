// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Observation
import SafiraCore

/// The side of the sidebar, one setting for the whole app: every window follows it as it changes.
@MainActor
@Observable
final class SidebarSideSetting {
    @ObservationIgnored private let store = SidebarSideStore()

    var side: SidebarSide {
        didSet { store.save(side) }
    }

    init(preferenceProblems: PreferenceProblems) {
        side = store.load(unreadable: preferenceProblems.record)
    }

    var isRight: Bool {
        get { side == .right }
        set { side = newValue ? .right : .left }
    }
}
