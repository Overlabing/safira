// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DesignKit
import DownloadsUI
import Observation
import SafiraCore
import SafiraSession
import SafiraWeb
import SwiftUI

/// Whether a window's downloads panel is open: its button toggles it, and so does the menu's Downloads item (⌥⌘L).
@MainActor
@Observable
final class DownloadsPresenter {
    var isPresented = false
}

/// The downloads button of a sidebar's footer, and the panel it opens in a popover. It shows while the list has
/// something to say (`DownloadsIndicator.isVisible`), and while the panel is open, so that ⌥⌘L can open an empty one.
struct SidebarDownloads: View {
    let downloads: ProfileDownloads
    let web: ProfileWebContext
    @Bindable var presenter: DownloadsPresenter

    var body: some View {
        if downloads.indicator.isVisible || presenter.isPresented {
            DownloadsButton(indicator: downloads.indicator) { presenter.isPresented.toggle() }
                .popover(isPresented: $presenter.isPresented, arrowEdge: .top) {
                    DownloadsPanel(downloads: downloads, folder: folder)
                        // macOS asks for the Downloads folder the first time it is needed; asking here, when the user
                        // opened the list, keeps that prompt from appearing in the middle of a page's download.
                        .task { await web.prepareDownloadsAccess() }
                }
        }
    }

    private var folder: DownloadsFolder {
        DownloadsFolder(url: downloads.savesInAppFolder ? web.downloadsFallbackDirectory : web.downloadsDirectory,
                        isAppFolder: downloads.savesInAppFolder)
    }
}
