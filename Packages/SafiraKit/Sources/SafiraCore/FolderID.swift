// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// Identifies a Folder inside its Profile.
public struct FolderID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public init?(uuidString: String) {
        guard let uuid = UUID(uuidString: uuidString) else { return nil }
        self.init(rawValue: uuid)
    }
}

/// What sits in a Space's pinned area or inside a Folder: a Pinned tab or a Folder, never a plain Tab.
public enum PinnedItemID: Hashable, Sendable {
    case tab(TabID)
    case folder(FolderID)
}
