// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// Settings Safira no longer has. Their saved values are removed at launch, so nothing can read them again.
public enum RetiredPreferences {
    /// The side of the sidebar (#116): the sidebar is always on the left.
    public static let keys = ["window.sidebarSide"]

    public static func remove(from defaults: UserDefaults) {
        for key in keys { defaults.removeObject(forKey: key) }
    }
}
