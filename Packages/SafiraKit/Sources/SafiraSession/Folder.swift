// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Observation
import SafiraCore

/// What sits in a Space's pinned area or inside a Folder. A plain Tab has no case here, so a Folder cannot hold one.
public enum PinnedItem: Identifiable {
    case tab(Tab)
    case folder(Folder)

    public var id: PinnedItemID {
        switch self {
        case .tab(let tab): .tab(tab.id)
        case .folder(let folder): .folder(folder.id)
        }
    }
}

/// A container inside a Space that holds only Pinned tabs and other Folders. Only its `ProfileSession` changes it.
@MainActor
@Observable
public final class Folder: Identifiable {
    public let id: FolderID
    public internal(set) var name: String
    public internal(set) var isExpanded: Bool
    public internal(set) var items: [PinnedItem]

    init(id: FolderID, name: String, isExpanded: Bool = true, items: [PinnedItem] = []) {
        self.id = id
        self.name = name
        self.isExpanded = isExpanded
        self.items = items
    }

    var record: FolderRecord {
        FolderRecord(id: id, name: name, isExpanded: isExpanded, items: items.map(\.record))
    }

    /// Every Pinned tab inside, depth first.
    var pinnedTabs: [Tab] {
        items.pinnedTabs
    }

    /// Whether this Folder is `id` or holds it, at any depth.
    func contains(folder id: FolderID) -> Bool {
        self.id == id || items.contains { item in
            if case .folder(let folder) = item { folder.contains(folder: id) } else { false }
        }
    }
}

extension PinnedItem {
    @MainActor var record: PinnedItemRecord {
        switch self {
        case .tab(let tab): .tab(tab.record)
        case .folder(let folder): .folder(folder.record)
        }
    }
}

extension [PinnedItem] {
    /// Every Pinned tab, depth first, in the order the pinned area shows them.
    @MainActor var pinnedTabs: [Tab] {
        flatMap { item -> [Tab] in
            switch item {
            case .tab(let tab): [tab]
            case .folder(let folder): folder.pinnedTabs
            }
        }
    }

    /// Every Folder, depth first.
    @MainActor var folders: [Folder] {
        flatMap { item -> [Folder] in
            if case .folder(let folder) = item { [folder] + folder.items.folders } else { [] }
        }
    }
}
