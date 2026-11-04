// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics

extension ProfileSession {
    /// How many of the Profile's Tabs, in every Space, are blank, loading or loaded, for Debug mode. It reads no
    /// address or title.
    public var diagnosticTabCounts: TabCounts {
        allTabs.reduce(into: TabCounts()) { counts, tab in
            if tab.state.isLoading {
                counts.loading += 1
            } else if tab.state.url == nil {
                counts.blank += 1
            } else {
                counts.loaded += 1
            }
        }
    }
}
