// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraStore

extension StoreLayout {
    /// Safira's folder in Application Support, inside the app's container.
    static var application: StoreLayout {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let bundleID = Bundle.main.bundleIdentifier ?? "com.overlabing.safira"
        return StoreLayout(root: support.appending(path: bundleID, directoryHint: .isDirectory))
    }
}
