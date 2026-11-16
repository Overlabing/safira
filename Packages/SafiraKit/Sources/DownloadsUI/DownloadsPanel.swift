// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import DesignKit
import SafiraCore
import SafiraSession
import SwiftUI
import UniformTypeIdentifiers

/// Where the panel's downloads are saved, as its footer says it.
public struct DownloadsFolder: Sendable, Equatable {
    public var url: URL
    /// The user declined access to the Downloads folder, so files go to Safira's own folder.
    public var isAppFolder: Bool

    public init(url: URL, isAppFolder: Bool) {
        self.url = url
        self.isAppFolder = isAppFolder
    }
}

/// What the panel asks of the app: the file system, which the views do not touch themselves.
@MainActor
public struct DownloadsPanelActions {
    public var open: (URL) -> Void
    public var reveal: (URL) -> Void

    public init(open: @escaping (URL) -> Void, reveal: @escaping (URL) -> Void) {
        self.open = open
        self.reveal = reveal
    }

    public static let workspace = DownloadsPanelActions(
        open: { NSWorkspace.shared.open($0) },
        reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) })
}

/// The downloads panel, shown in a popover from the sidebar's downloads button: one Profile's downloads (or one
/// Private window's), newest first, then the folder in use and Clear. It draws no background: the popover is its glass.
public struct DownloadsPanel: View {
    @Environment(\.designTokens) private var tokens
    private let downloads: ProfileDownloads
    private let folder: DownloadsFolder
    private let actions: DownloadsPanelActions
    private let now: () -> Date

    public init(downloads: ProfileDownloads, folder: DownloadsFolder, actions: DownloadsPanelActions = .workspace,
                now: @escaping () -> Date = { Date() }) {
        self.downloads = downloads
        self.folder = folder
        self.actions = actions
        self.now = now
    }

    public static let width: CGFloat = 360

    public var body: some View {
        let spacing = tokens.spacing
        WithColorRoles { roles in
            VStack(alignment: .leading, spacing: 0) {
                Text("Downloads", tableName: "DownloadsUI", bundle: .module, comment: "Downloads panel: its title")
                    .role(tokens.type.sectionHeader)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, spacing.listMargin)
                    .padding(.top, spacing.listMargin)
                    .padding(.bottom, spacing.sectionHeaderBottom)
                if downloads.all.isEmpty {
                    Text("No downloads yet. Files you download appear here.", tableName: "DownloadsUI", bundle: .module,
                         comment: "Downloads panel: an empty list")
                        .role(tokens.type.rowDetail)
                        .foregroundStyle(roles.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: tokens.size.compactRow * 2)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(downloads.all) { download in
                                DownloadRow(download: download, downloads: downloads, actions: actions, now: now)
                            }
                        }
                        .padding(.horizontal, spacing.listMargin - spacing.rowInsetHorizontal)
                    }
                    .frame(maxHeight: tokens.size.compactRow * 8)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(roles.columnEdge).frame(height: tokens.size.hairline)
                footer(roles)
            }
            .frame(width: Self.width)
        }
        .onAppear { downloads.markFailuresSeen() }
    }

    private func footer(_ roles: ColorRoles) -> some View {
        let spacing = tokens.spacing
        return VStack(alignment: .leading, spacing: spacing.textLines) {
            if folder.isAppFolder {
                Text("You declined access to your Downloads folder, so files are saved in Safira's own folder, which is erased with the Profile. You can allow access in System Settings > Privacy & Security > Files & Folders.",
                     tableName: "DownloadsUI", bundle: .module, comment: "Downloads panel: the folder in use")
                    .role(tokens.type.rowDetail)
                    .foregroundStyle(roles.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: spacing.pillActionGap) {
                Button { actions.reveal(folder.url) } label: {
                    Label {
                        Text(verbatim: FileManager.default.displayName(atPath: folder.url.path(percentEncoded: false)))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } icon: {
                        Image(systemName: "folder")
                    }
                    .font(tokens.type.rowDetail.font)
                }
                .buttonStyle(PressedOpacityStyle())
                .foregroundStyle(roles.secondaryText)
                .help(Text("Show the folder in Finder", tableName: "DownloadsUI", bundle: .module,
                           comment: "Downloads panel: the folder button's help tag"))
                .accessibilityLabel(Text("Show folder \(folder.url.lastPathComponent) in Finder", tableName: "DownloadsUI",
                                         bundle: .module, comment: "Downloads panel"))
                Spacer(minLength: spacing.pillActionGap)
                IconButton(String(localized: "Clear", table: "DownloadsUI", bundle: .module,
                                  comment: "Downloads panel: takes finished downloads off the list, not the files")) {
                    downloads.removeFinished()
                }
                .disabled(!downloads.canClear)
            }
        }
        .padding(.horizontal, spacing.listMargin)
        .padding(.vertical, spacing.rowInsetVertical + spacing.textLines)
    }
}

/// One download: its file icon, name and state line (and a bar while it runs), the actions of its state, a menu with
/// all of them. A finished file opens on a double click and can be dragged out.
struct DownloadRow: View {
    @Environment(\.designTokens) private var tokens
    let download: DownloadRecord
    let downloads: ProfileDownloads
    let actions: DownloadsPanelActions
    let now: () -> Date
    @State private var isHovered = false

    var body: some View {
        let spacing = tokens.spacing
        let file = download.state == .completed ? download.savedFileURL() : nil
        WithColorRoles { roles in
            HStack(alignment: .center, spacing: spacing.compactTileToText) {
                FileIcon(fileName: download.fileName, file: file, size: tokens.size.compactTile)
                VStack(alignment: .leading, spacing: spacing.textLines) {
                    Text(verbatim: download.fileName)
                        .role(tokens.type.rowTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if download.state == .active || download.state == .paused {
                        ProgressView(value: download.fractionCompleted ?? 0)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                            .tint(roles.selectionMarker)
                            .opacity(download.fractionCompleted == nil ? tokens.emphasis.disabled : 1)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: status)
                        .role(tokens.type.rowDetail)
                        .foregroundStyle(download.state == .failed ? Color(nsColor: .systemRed) : roles.secondaryText)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                HStack(spacing: 0) { buttons(file: file) }
            }
            .padding(.vertical, spacing.rowInsetVertical + spacing.textLines)
            .padding(.horizontal, spacing.rowInsetHorizontal)
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: tokens.radius.row, style: .continuous).fill(roles.hoverFill)
                }
            }
            .contentShape(.rect)
            .onHover { isHovered = $0 }
            .onTapGesture(count: 2) { if let file { actions.open(file) } }
            .modifier(FileDrag(file: file))
            .contextMenu { menu(file: file) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: "\(download.fileName), \(status)"))
        }
    }

    private var status: String {
        DownloadText.status(of: download, timeRemaining: downloads.timeRemaining(download.id),
                            failure: downloads.failure(download.id), now: now())
    }

    @ViewBuilder
    private func buttons(file: URL?) -> some View {
        switch download.state {
        case .active:
            IconButton(Self.pauseTitle, systemImage: "pause.fill") { Task { await downloads.pause(download.id) } }
            IconButton(Self.cancelTitle, systemImage: "xmark") { Task { await downloads.cancel(download.id) } }
        case .paused:
            IconButton(Self.resumeTitle, systemImage: "play.fill") { downloads.resume(download.id) }
            IconButton(Self.cancelTitle, systemImage: "xmark") { Task { await downloads.cancel(download.id) } }
        case .completed:
            IconButton(Self.revealTitle, systemImage: "magnifyingglass") { if let file { actions.reveal(file) } }
                .disabled(file == nil)
        case .failed, .cancelled:
            IconButton(Self.retryTitle, systemImage: "arrow.clockwise") { downloads.retry(download.id) }
            IconButton(Self.removeTitle, systemImage: "xmark") { downloads.remove(download.id) }
        }
    }

    @ViewBuilder
    private func menu(file: URL?) -> some View {
        switch download.state {
        case .active:
            Button(Self.pauseTitle) { Task { await downloads.pause(download.id) } }
            Button(Self.cancelTitle) { Task { await downloads.cancel(download.id) } }
        case .paused:
            Button(Self.resumeTitle) { downloads.resume(download.id) }
            Button(Self.cancelTitle) { Task { await downloads.cancel(download.id) } }
        case .completed:
            Button(Self.openTitle) { if let file { actions.open(file) } }.disabled(file == nil)
            Button(Self.revealTitle) { if let file { actions.reveal(file) } }.disabled(file == nil)
        case .failed, .cancelled:
            Button(Self.retryTitle) { downloads.retry(download.id) }
        }
        if download.state != .active {
            Divider()
            Button(Self.removeTitle) { downloads.remove(download.id) }
        }
    }

    static let pauseTitle = String(localized: "Pause", table: "DownloadsUI", bundle: .module, comment: "Downloads panel: row action")
    static let resumeTitle = String(localized: "Resume", table: "DownloadsUI", bundle: .module, comment: "Downloads panel: row action")
    static let cancelTitle = String(localized: "Cancel", table: "DownloadsUI", bundle: .module, comment: "Downloads panel: row action")
    static let openTitle = String(localized: "Open", table: "DownloadsUI", bundle: .module, comment: "Downloads panel: row action")
    static let revealTitle = String(localized: "Show in Finder", table: "DownloadsUI", bundle: .module, comment: "Downloads panel: row action")
    static let retryTitle = String(localized: "Retry", table: "DownloadsUI", bundle: .module, comment: "Downloads panel: row action")
    static let removeTitle = String(localized: "Remove from List", table: "DownloadsUI", bundle: .module, comment: "Downloads panel: row action")
}

/// A finished file can be dragged out of its row, to Finder or another app, as the file itself.
private struct FileDrag: ViewModifier {
    let file: URL?

    func body(content: Content) -> some View {
        if let file {
            content.onDrag { NSItemProvider(contentsOf: file) ?? NSItemProvider() }
        } else {
            content
        }
    }
}

/// The file's own icon once it is saved, its type's icon before.
private struct FileIcon: View {
    let fileName: String
    let file: URL?
    let size: CGFloat

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private var icon: NSImage {
        if let file { return NSWorkspace.shared.icon(forFile: file.path(percentEncoded: false)) }
        let type = UTType(filenameExtension: URL(fileURLWithPath: fileName).pathExtension) ?? .data
        return NSWorkspace.shared.icon(for: type)
    }
}
