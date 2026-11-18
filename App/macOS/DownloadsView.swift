// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DesignKit
import DownloadsUI
import SafiraCore
import SafiraSettings
import SafiraSession
import SwiftUI

/// The bottom-left buttons of a sidebar, as in Zen: the Library, and while the downloads have something to say
/// (`DownloadsIndicator.isVisible`), the downloads button with its progress, which opens the Library on Downloads.
struct SidebarLibraryButtons: View {
    let downloads: ProfileDownloads
    let open: (LibraryDestination) -> Void

    var body: some View {
        HStack(spacing: DesignTokens.standard.spacing.sidebarHeadButtonGap) {
            IconButton(String(localized: "Library", comment: "Sidebar: the button that opens the Library"),
                       systemImage: "books.vertical") { open(.settings(nil)) }
                .help(String(localized: "Library: Downloads, Spaces, Link Rules, Extensions and Settings",
                             comment: "Sidebar: help tag of the Library button"))
            if downloads.indicator.isVisible {
                DownloadsButton(indicator: downloads.indicator) { open(.item(.downloads)) }
            }
        }
    }
}
