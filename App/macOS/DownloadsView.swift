// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore
import SafiraSession
import SafiraWeb
import SwiftUI

/// The downloads of the Active profile, and of no other: the list follows the Profile the Main window shows.
struct DownloadsView: View {
    let registry: ProfileRegistry

    var body: some View {
        let downloads = registry.active.downloads
        VStack(alignment: .leading, spacing: 12) {
            Text("Downloads of “\(registry.activeProfile.name)”")
                .font(.headline)
            if downloads.all.isEmpty {
                Text("This Profile has no downloads.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List(downloads.all) { download in
                    DownloadRow(download: download, downloads: downloads)
                }
                .frame(minHeight: 200)
            }
            HStack {
                if downloads.savesInAppFolder {
                    Text("You declined access to your Downloads folder, so files are saved in Safira's own folder. You can allow it in System Settings > Privacy & Security > Files & Folders.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Show Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([registry.active.web.downloadsFallbackDirectory])
                    }
                } else {
                    Text("Files are saved in your Downloads folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear List") { downloads.removeFinished() }
                    .disabled(!downloads.all.contains { $0.state != .active })
            }
        }
        .padding(16)
        .frame(minWidth: 460, minHeight: 280)
        // macOS asks for the Downloads folder the first time it is needed; asking here, when the user opened the
        // list, keeps that prompt from appearing in the middle of a page's download.
        .task(id: registry.activeProfileID) { await registry.active.web.prepareDownloadsAccess() }
    }
}

private struct DownloadRow: View {
    let download: DownloadRecord
    let downloads: ProfileDownloads

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: download.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if download.state == .active {
                    if let fraction = download.fractionCompleted {
                        ProgressView(value: fraction)
                            .accessibilityLabel(Text("Progress of \(download.fileName)"))
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            actions
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actions: some View {
        switch download.state {
        case .active:
            Button("Cancel") { Task { await downloads.cancel(download.id) } }
                .accessibilityLabel(Text("Cancel download of \(download.fileName)"))
        case .completed:
            Button("Reveal in Finder") { reveal() }
                .disabled(download.savedFileURL() == nil)
                .accessibilityLabel(Text("Reveal \(download.fileName) in Finder"))
            remove
        case .cancelled, .failed:
            Button("Retry") { downloads.retry(download.id) }
                .accessibilityLabel(Text("Retry download of \(download.fileName)"))
            remove
        }
    }

    private var remove: some View {
        Button("Remove from List") { downloads.remove(download.id) }
            .accessibilityLabel(Text("Remove \(download.fileName) from the list"))
    }

    private func reveal() {
        guard let url = download.savedFileURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private var status: String {
        let format = ByteCountFormatter()
        func size(_ bytes: Int64) -> String { format.string(fromByteCount: bytes) }
        switch download.state {
        case .active:
            if let total = download.totalBytes {
                return String(localized: "\(size(download.receivedBytes)) of \(size(total))")
            }
            return size(download.receivedBytes)
        case .completed:
            return String(localized: "Completed, \(size(download.receivedBytes))")
        case .cancelled:
            return String(localized: "Cancelled, \(size(download.receivedBytes)) received")
        case .failed:
            return String(localized: "Failed, \(size(download.receivedBytes)) received")
        }
    }
}

/// The Downloads window: not modal, so a download can be watched while the Main window is used.
@MainActor
final class DownloadsWindowController: NSWindowController {
    init(registry: ProfileRegistry) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: DownloadsView(registry: registry)))
        window.title = String(localized: "Downloads")
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("DownloadsWindow")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}
