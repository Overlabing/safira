// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore
import SafiraWeb
import SwiftUI
import UniformTypeIdentifiers

/// Settings › Extensions: the extensions installed for the app, each with a switch per Profile, what it may do, and
/// Remove; and the two ways to install one. It reads the folders of extensions installed from a folder again whenever
/// it appears, so an update shows at once.
struct ExtensionsPane: View {
    let registry: ProfileRegistry
    @State private var removing: InstalledExtension?

    private var library: ExtensionLibrary { registry.extensionLibrary }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("An extension is installed once for Safira and runs in every Profile whose switch is on. A Profile created later starts with it on. Extensions never run in Private windows.",
                 comment: "Settings, Extensions pane")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(String(localized: "Add from Folder…", comment: "Settings, Extensions pane: button")) { addFromFolder() }
                Button(String(localized: "Add from File…", comment: "Settings, Extensions pane: button")) { addFromFile() }
            }
            if library.installed.isEmpty {
                Text("No extension is installed. Add one from a folder that holds its manifest.json, or from a .zip or .crx file.",
                     comment: "Settings, Extensions pane: empty list")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .settingsGroup()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(library.installed) { item in
                            ExtensionRow(item: item, status: library.statuses[item.id] ?? ExtensionStatus(),
                                         profiles: registry.profiles,
                                         setEnabled: { on, profile in
                                             Task { await library.setEnabled(on, extension: item.id, in: profile) }
                                         },
                                         locate: { locate(item) },
                                         review: { Task { await library.allowPending(item.id) } },
                                         reload: { Task { await library.reload(item.id) } },
                                         remove: { removing = item })
                        }
                    }
                }
                .settingsScrollEdges()
            }
        }
        .task {
            await library.checkForUpdates()
            #if DEBUG
            await ExtensionInstallPreview.run { install(from: $0) }
            #endif
        }
        .confirmationDialog(removalTitle, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { item in
            Button(String(localized: "Remove", comment: "Settings, Extensions pane: confirmation button"), role: .destructive) {
                Task { await library.remove(item.id) }
            }
        } message: { _ in
            Text("It stops in every Profile, and what it stored in each Profile is deleted. Its folder or file is not touched.",
                 comment: "Settings, Extensions pane: removal confirmation")
        }
    }

    private var removalTitle: String {
        String(localized: "Remove “\(removing?.displayName ?? "")”?",
               comment: "Settings, Extensions pane: removal confirmation; the argument is an extension's name")
    }

    private func addFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Add", comment: "Open panel button of Add from Folder")
        panel.message = String(localized: "Choose the folder that holds the extension’s manifest.json. Safira reads it where it is, so updates to the folder reach Safira.",
                               comment: "Open panel message of Add from Folder")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        install(from: folder)
    }

    private func addFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip] + [UTType(filenameExtension: "crx")].compactMap(\.self)
        panel.prompt = String(localized: "Add", comment: "Open panel button of Add from File")
        panel.message = String(localized: "Choose the extension’s .zip or .crx file. Safira keeps a copy of it.",
                               comment: "Open panel message of Add from File")
        guard panel.runModal() == .OK, let file = panel.url else { return }
        install(from: file)
    }

    private func install(from url: URL) {
        Task {
            do {
                try await library.install(from: url)
            } catch {
                UserFacingAlert.runModal(.extensionNotInstalled(error))
            }
        }
    }

    private func locate(_ item: InstalledExtension) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose", comment: "Open panel button of Locate")
        panel.message = String(localized: "Choose the folder that now holds “\(item.displayName)”.",
                               comment: "Open panel message of Locate; the argument is an extension's name")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task {
            do {
                try await library.locate(item.id, at: folder)
            } catch {
                UserFacingAlert.runModal(.extensionNotLocated(error))
            }
        }
    }
}

#if DEBUG
/// A capture of the permission sheet needs an install: the launch argument `-SafiraExtensionPreviewAsk <folder>` installs
/// that folder once, through the sheet, when the Extensions pane first appears. Debug builds only, for a copy under a
/// throwaway bundle id.
@MainActor
private enum ExtensionInstallPreview {
    private static var didRun = false

    static func run(install: (URL) -> Void) async {
        guard !didRun, let path = UserDefaults.standard.string(forKey: "SafiraExtensionPreviewAsk") else { return }
        didRun = true
        try? await Task.sleep(for: .seconds(1))
        install(URL(filePath: path, directoryHint: .isDirectory))
    }
}
#endif

/// One installed extension: its icon, name and version, what it may do, a switch per Profile, and Remove. A folder
/// that cannot be found, or that now holds another extension, is said so, with Locate…; what an update asked for and
/// the user did not allow is said so, with Review…; a service worker or background page that could not start is said
/// so with WebKit's reason, with Reload.
private struct ExtensionRow: View {
    let item: InstalledExtension
    let status: ExtensionStatus
    let profiles: [Profile]
    let setEnabled: (Bool, ProfileID) -> Void
    let locate: () -> Void
    let review: () -> Void
    let reload: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: item.displayName)
                        .font(.headline)
                    Text(verbatim: item.version)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Remove…", comment: "Settings, Extensions pane: button"), action: remove)
                        .accessibilityLabel(Text("Remove \(item.displayName)", comment: "Settings, Extensions pane: VoiceOver label; the argument is an extension's name"))
                }
                availability
                if let failure = status.backgroundFailure {
                    backgroundFailure(failure)
                }
                if status.pendingRequest != nil {
                    HStack {
                        Label(String(localized: "This version asks for more than you allowed. It runs with what you allowed before.",
                                     comment: "Settings, Extensions pane: an update whose permission sheet was cancelled"),
                              systemImage: "exclamationmark.shield")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button(String(localized: "Review…", comment: "Settings, Extensions pane: button that shows the permission sheet again"),
                               action: review)
                    }
                    .font(.callout)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(summary, id: \.self) { line in
                        Text(verbatim: line)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    ForEach(profiles) { profile in
                        GridRow {
                            Text(verbatim: "\(profile.symbol)  \(profile.name)")
                                .accessibilityHidden(true)
                            Toggle(isOn: Binding(get: { item.isEnabled(in: profile.id) },
                                                 set: { setEnabled($0, profile.id) })) {
                                Text("\(item.displayName) in “\(profile.name)”",
                                     comment: "Settings, Extensions pane: VoiceOver label of a Profile's switch; the arguments are an extension's and a Profile's names")
                            }
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsGroup()
    }

    private func backgroundFailure(_ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text("Couldn’t start: \(reason)",
                         comment: "Settings, Extensions pane: an extension whose service worker or background page failed to start; the argument is the error WebKit reports")
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .foregroundStyle(.orange)
                Spacer()
                Button(String(localized: "Reload", comment: "Settings, Extensions pane: button that reads an extension's files again and starts it again"),
                       action: reload)
                    .accessibilityLabel(Text("Reload \(item.displayName)", comment: "Settings, Extensions pane: VoiceOver label; the argument is an extension's name"))
            }
            if status.startsAtNextLaunch {
                Text("It still fails after Reload. Once its files are fixed, it starts the next time Safira opens.",
                     comment: "Settings, Extensions pane: WebKit does not start an extension's service worker again in a run where it failed")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
    }

    private var icon: some View {
        Group {
            if let image = status.icon {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "puzzlepiece.extension").resizable().scaledToFit().padding(4).foregroundStyle(.secondary)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var availability: some View {
        switch status.availability {
        case .available:
            if !status.errors.isEmpty {
                Label {
                    Text(verbatim: status.errors.joined(separator: "\n"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.callout)
                .foregroundStyle(.orange)
            }
        case .missing:
            HStack {
                Label(String(localized: "Safira can’t find this extension’s files, so it does not run.",
                             comment: "Settings, Extensions pane: an extension whose folder or copy is gone"),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
                if case .folder = item.source {
                    Button(String(localized: "Locate…", comment: "Settings, Extensions pane: button"), action: locate)
                }
            }
            .font(.callout)
        case .differentExtension:
            HStack {
                Label(String(localized: "Its folder now holds another extension, so it does not run.",
                             comment: "Settings, Extensions pane: an extension whose folder was replaced by another extension"),
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
                Button(String(localized: "Locate…", comment: "Settings, Extensions pane: button"), action: locate)
            }
            .font(.callout)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    private var summary: [String] {
        let lines = ExtensionPermissionWording.lines(permissions: item.grantedPermissions,
                                                     matchPatterns: item.grantedMatchPatterns,
                                                     hasAccessToAllHosts: status.hasAccessToAllHosts)
        return lines.isEmpty
            ? [String(localized: "Asks for no permission", comment: "Settings, Extensions pane: an extension with no permission")]
            : lines
    }
}

/// The permission sheet: what an extension asks for, worded as Safari words it, once at install, once when an update
/// asks for more, and when the extension asks at run time. Allow grants everything listed; Cancel grants nothing (and
/// at install, installs nothing). It is a sheet on the window the user is in, one question at a time.
@MainActor
final class ExtensionPermissionPrompter {
    private let window: () -> NSWindow?
    private var tail: Task<Void, Never>?

    init(window: @escaping () -> NSWindow?) {
        self.window = window
    }

    func ask(_ request: ExtensionPermissionRequest) async -> Bool {
        let previous = tail
        let turn = Task { @MainActor in
            await previous?.value
            return await self.show(request)
        }
        tail = Task { _ = await turn.value }
        return await turn.value
    }

    private func show(_ request: ExtensionPermissionRequest) async -> Bool {
        let alert = NSAlert()
        alert.icon = request.icon ?? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil)
        let name = request.displayName
        switch request.moment {
        case .install:
            alert.messageText = String(localized: "Install “\(name)”?", comment: "Extension permission sheet title; the argument is an extension's name")
            alert.informativeText = String(localized: "It will run in every Profile, never in Private windows. You can turn it off for a Profile in Settings › Extensions.",
                                           comment: "Extension permission sheet")
        case .update:
            alert.messageText = String(localized: "“\(name)” was updated and asks for more", comment: "Extension permission sheet title; the argument is an extension's name")
            alert.informativeText = String(localized: "If you don’t allow it, the extension keeps only what you allowed before. You can allow it later in Settings › Extensions.",
                                           comment: "Extension permission sheet")
        case .runtime:
            alert.messageText = String(localized: "“\(name)” asks for more", comment: "Extension permission sheet title; the argument is an extension's name")
            alert.informativeText = String(localized: "What you allow applies in every Profile.", comment: "Extension permission sheet")
        }
        alert.accessoryView = Self.details(of: request)
        alert.addButton(withTitle: String(localized: "Allow", comment: "Extension permission sheet button"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Extension permission sheet button")).keyEquivalent = "\u{1b}"
        let response: NSApplication.ModalResponse
        if let window = window(), window.isVisible {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        return response == .alertFirstButtonReturn
    }

    /// "It can:" with one line per thing it could do, then the manifest's own names, smaller.
    private static func details(of request: ExtensionPermissionRequest) -> NSView {
        let lines = request.summary.isEmpty
            ? [String(localized: "It asks for no permission.", comment: "Extension permission sheet")]
            : request.summary.map { "•  \($0)" }
        let summary = NSTextField(wrappingLabelWithString: lines.joined(separator: "\n"))
        summary.font = .systemFont(ofSize: NSFont.systemFontSize)
        let raw = (request.permissions + request.matchPatterns).joined(separator: ", ")
        let names = NSTextField(wrappingLabelWithString: raw.isEmpty ? "" : String(localized: "Asks for: \(raw)",
                                                                                     comment: "Extension permission sheet; the argument lists permission names and websites as the manifest writes them"))
        names.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        names.textColor = .secondaryLabelColor
        let stack = NSStackView(views: raw.isEmpty ? [summary] : [summary, names])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        let width: CGFloat = 300
        for field in [summary, names] {
            field.preferredMaxLayoutWidth = width
            field.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
        return stack
    }
}
