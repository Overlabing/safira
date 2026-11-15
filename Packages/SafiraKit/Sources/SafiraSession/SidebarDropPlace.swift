// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore

/// Where a Tab or Folder dragged in the sidebar lands: a gap of the pinned area's top or of one Folder, or a gap of the
/// Space's other Tabs. `index` is the gap as the sidebar shows it, counted with the dragged item still in place: 0 is
/// before the first item, the item count is after the last.
public enum SidebarDropPlace: Hashable, Sendable {
    case pinned(folder: FolderID?, index: Int)
    case tabs(index: Int)
}
