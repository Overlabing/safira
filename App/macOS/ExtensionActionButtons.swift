// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import DesignKit
import SafiraWeb
import SwiftUI
import WebKit

/// The Active profile's extension actions in the sidebar's head row, after Reload: one button per extension, or one
/// "Extensions" overflow button that lists them once there are more than two. Each button shows the action's icon
/// and badge for the active Tab; a click performs the action, which may open its popup under the button.
struct ExtensionActionButtons: View {
    let host: ExtensionHost
    let popups: ExtensionPopups

    var body: some View {
        HStack(spacing: 0) {
            switch host.actions.layout {
            case .buttons:
                ForEach(host.actions.items) { item in
                    ExtensionActionButton(item: item) { host.performAction(extensionID: item.id) }
                        .background(PopupAnchor(key: .action(item.id), popups: popups))
                }
            case .overflow:
                ExtensionOverflowButton(items: host.actions.items) { host.performAction(extensionID: $0) }
                    .background(PopupAnchor(key: .overflow, popups: popups))
            }
        }
        .onAppear { popups.serve(host) }
        .onChange(of: ObjectIdentifier(host)) { popups.serve(host) }
        #if DEBUG
        .task { await ExtensionActionPreview.run(host: host) }
        #endif
    }
}

/// One extension's button: its icon in the kit's toolbar button size, its badge on the icon's corner in the Theme's
/// badge fill. VoiceOver reads the extension's name and its badge; the help tag shows the action's title.
private struct ExtensionActionButton: View {
    let item: ExtensionActionItem
    let perform: () -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let side = max(tokens.size.toolbarButton, tokens.size.minTarget)
        Button(action: perform) {
            ExtensionIcon(icon: item.icon)
                .frame(width: side, height: side)
                .overlay(alignment: .topTrailing) {
                    if !item.badgeText.isEmpty {
                        ExtensionBadge(text: item.badgeText)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(PressedOpacityStyle())
        .disabled(!item.isEnabled)
        .opacity(item.isEnabled ? 1 : 0.45)
        .help(item.label)
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(Text(verbatim: item.badgeText))
        .accessibilityHint(Text("Performs the extension's action", comment: "Sidebar: VoiceOver hint of an extension's button"))
    }
}

/// The badge on the icon's corner, in the Theme's band colour: the kit's translucent badge fill would vanish over the
/// icon it overlaps.
private struct ExtensionBadge: View {
    let text: String
    @Environment(\.designTokens) private var tokens

    var body: some View {
        WithColorRoles { roles in
            Text(verbatim: text)
                .role(tokens.type.count)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(roles.bandText)
                .padding(.horizontal, tokens.spacing.badgeVertical)
                .frame(minWidth: 14)
                .background(roles.bandFill, in: Capsule(style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// The overflow button: a puzzle piece whose menu lists each extension with its icon, title and badge.
private struct ExtensionOverflowButton: View {
    let items: [ExtensionActionItem]
    let perform: (String) -> Void
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let side = max(tokens.size.toolbarButton, tokens.size.minTarget)
        WithColorRoles { roles in
            Menu {
                ForEach(items) { item in
                    Button { perform(item.id) } label: {
                        if let icon = item.icon {
                            Label { Text(verbatim: Self.title(of: item)) } icon: { Image(nsImage: icon) }
                        } else {
                            Text(verbatim: Self.title(of: item))
                        }
                    }
                    .disabled(!item.isEnabled)
                }
            } label: {
                Image(systemName: "puzzlepiece.extension")
                    .frame(width: side, height: side)
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(PressedOpacityStyle())
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(roles.secondaryText)
            .help(String(localized: "Extensions", comment: "Sidebar: help tag of the button that lists the extensions"))
            .accessibilityLabel(Text("Extensions", comment: "Sidebar: VoiceOver label of the button that lists the extensions"))
            .accessibilityValue(Text(verbatim: items.map(Self.spoken).joined(separator: ", ")))
        }
    }

    /// "Verrou (3)": the title with the badge, which the menu has no other place for.
    static func title(of item: ExtensionActionItem) -> String {
        item.badgeText.isEmpty ? item.label : "\(item.label) (\(item.badgeText))"
    }

    static func spoken(_ item: ExtensionActionItem) -> String {
        item.badgeText.isEmpty ? item.name : "\(item.name) \(item.badgeText)"
    }
}

/// The action's icon at 16 points; a puzzle piece when the extension has none.
private struct ExtensionIcon: View {
    let icon: NSImage?

    var body: some View {
        WithColorRoles { roles in
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundStyle(roles.secondaryText)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// Shows extensions' popups in the Main window: each under its own button, or under the overflow button for an
/// extension listed in there, `action.openPopup()` from a service worker included. The popover closes on Escape and
/// on a click outside it, which closes the popup's page.
@MainActor
final class ExtensionPopups {
    enum AnchorKey: Hashable {
        case action(String)
        case overflow
    }

    private var anchors: [AnchorKey: WeakView] = [:]
    private weak var served: ExtensionHost?

    /// Makes this window the one that shows the popups of `host`'s extensions: the Active profile's.
    func serve(_ host: ExtensionHost) {
        if let served, served !== host { served.popupPresenter = nil }
        served = host
        host.popupPresenter = { [weak self] id, action in
            guard let self else { throw ExtensionPopupUnavailable() }
            try self.present(action, for: id)
        }
    }

    func register(_ view: NSView, for key: AnchorKey) {
        anchors[key] = WeakView(view: view)
    }

    private func present(_ action: WKWebExtension.Action, for id: String) throws {
        let anchor = [AnchorKey.action(id), .overflow].lazy.compactMap { self.anchors[$0]?.view }
            .first { $0.window != nil }
        guard let anchor, let popover = action.popupPopover else { throw ExtensionPopupUnavailable() }
        popover.behavior = .transient
        if let screen = (anchor.window?.screen ?? NSScreen.main)?.visibleFrame {
            popover.contentSize = Self.capped(popover.contentSize, to: screen.size)
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
        #if DEBUG
        ExtensionActionPreview.snapshot(action.popupWebView)
        #endif
    }

    /// The popup's own size, within the screen less a margin for the popover's arrow and edges.
    static func capped(_ size: NSSize, to screen: NSSize) -> NSSize {
        let margin: CGFloat = 40
        return NSSize(width: min(size.width, screen.width - margin), height: min(size.height, screen.height - margin))
    }

    private struct WeakView {
        weak var view: NSView?
    }
}

/// An empty AppKit view behind a button, which the popover is anchored to.
private struct PopupAnchor: NSViewRepresentable {
    let key: ExtensionPopups.AnchorKey
    let popups: ExtensionPopups

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        popups.register(view, for: key)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        popups.register(view, for: key)
    }
}

#if DEBUG
/// Captures of the extension buttons and popups, which need an extension and a click: the launch argument
/// `-SafiraExtensionPreview <folder>` loads that folder into the Active profile once, and
/// `-SafiraExtensionPreviewPopup YES` then performs the first action, which opens its popup. Debug builds only; the
/// folder must be one the sandbox can read, such as the app's own temporary folder.
@MainActor
private enum ExtensionActionPreview {
    private static var didRun = false

    static func run(host: ExtensionHost) async {
        guard !didRun, let path = UserDefaults.standard.string(forKey: "SafiraExtensionPreview") else { return }
        didRun = true
        do {
            let loaded = try await host.loadUnpacked(at: URL(filePath: path, directoryHint: .isDirectory))
            guard UserDefaults.standard.bool(forKey: "SafiraExtensionPreviewPopup") else { return }
            try? await Task.sleep(for: .seconds(2))
            host.performAction(extensionID: loaded.identifier)
        } catch {
            NSLog("Extension preview: %@", String(describing: error))
        }
    }

    /// With `-SafiraExtensionPreviewPopup YES`, also writes the popup's page as `extension-popup.png` in the app's
    /// temporary folder: WebKit does not paint a page in a window other windows cover, which a capture of a Safira
    /// launched behind the frontmost app always is.
    static func snapshot(_ webView: WKWebView?) {
        guard let webView, UserDefaults.standard.bool(forKey: "SafiraExtensionPreviewPopup") else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            guard let image = try? await webView.takeSnapshot(configuration: nil),
                  let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { return }
            try? png.write(to: FileManager.default.temporaryDirectory.appending(path: "extension-popup.png"))
        }
    }
}
#endif
