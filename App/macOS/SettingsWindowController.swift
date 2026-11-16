// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Appearance
import AppShellKit
import ColorCore
import Commands
import DesignKit
import Onboarding
import Preferences
import SafiraCore
import SafiraSession
import SafiraSettings
import SafiraWeb
import SwiftUI

/// What the Settings window's panes draw: the controllers that hold each setting.
struct SettingsContent {
    let registry: ProfileRegistry
    let defaults: DefaultsController
    let links: LinkController
    let shortcuts: ShortcutController
    let updates: UpdateController
    let diagnostics: DiagnosticsController
    /// The active Space's Theme, under the window as under the Main window.
    let theme: @MainActor () -> Theme
}

/// The one Settings window: AppShellKit's shell with a pane per area. Safira › Settings… (⌘,) reopens the last pane;
/// Shortcuts…, Defaults…, Link Rules… and Site Permissions… open their own. The window is built the first time it is
/// shown: a window that exists without ever being shown still counts among the app's windows.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// Wider and taller than the kit's standard: the Link Rules pane holds a list, its tools and the check.
    static let metrics: SettingsShellMetrics = {
        var metrics = SettingsShellMetrics.standard
        metrics.windowWidth = 900
        metrics.windowHeight = 680
        metrics.contentWidth = 660
        return metrics
    }()

    /// The height left to a pane under the title bar and its header. A pane gets exactly this: offered the column's
    /// height, a pane holding a list took the height of all its rows and pushed the whole split view past the window.
    static let paneHeight: CGFloat = metrics.windowHeight - 150

    private let content: SettingsContent
    private let activates: Bool
    private(set) var presenter: SettingsPresenter!
    /// The switches of every pane, read again whenever the menu or another window may have changed them.
    private lazy var switches = content.defaults.makeSummaryModel()
    private var appearanceObservation: NSKeyValueObservation?

    /// - Parameter activates: false when Safira was started in the background, which it then never leaves.
    init(content: SettingsContent, activates: Bool) {
        self.content = content
        self.activates = activates
        super.init(window: nil)
        presenter = SettingsPresenter { [weak self] in self?.show() }
        NotificationCenter.default.addObserver(self, selector: #selector(menuDidEndTracking(_:)),
                                               name: NSMenu.didEndTrackingNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The action of every menu item that opens the window; the item's `representedObject` names its `SettingsOpener`.
    @objc func openSettings(_ sender: Any?) {
        let opener = ((sender as? NSMenuItem)?.representedObject as? String).flatMap(SettingsOpener.init(rawValue:))
        presenter.open(opener ?? .settings)
    }

    private func show() {
        let window = window ?? makeWindow()
        refresh()
        if !window.isVisible { window.center() }
        showWindow(nil)
        if activates { NSApp.activate() }
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView(model: presenter.model, switches: switches, content: content)
        let hosting = NSHostingController(rootView: root)
        // No bridging: the kit's `navigationTitle` would put the pane name back in the title bar, over the header.
        hosting.sceneBridgingOptions = []
        // The window keeps the shell's size: sized from the panes' ideal size, a list grew to all its rows and pushed the
        // pane past the window.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        // The pane header names the pane; the title bar shows no title of its own and no toolbar band, so the header
        // sits near the top, as in System Settings. The title stays set for VoiceOver and the Window menu.
        window.titleVisibility = .hidden
        // The Theme's gradient runs under the title bar, as the kit's shell expects.
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setContentSize(NSSize(width: Self.metrics.windowWidth, height: Self.metrics.windowHeight))
        window.delegate = self
        self.window = window
        followAppearance()
        followPaneTitle()
        return window
    }

    /// The window is titled after the open pane, as System Settings is, for VoiceOver and the Window menu: the kit's
    /// `navigationTitle` reaches no title bar from a hosting controller.
    private func followPaneTitle() {
        window?.title = withObservationTracking {
            presenter.model.current.title
        } onChange: { [weak self] in
            Task { @MainActor in self?.followPaneTitle() }
        }
    }

    /// The window's own appearance, set from the app's: a view drawn in the window reads its light or dark colours from
    /// the window, and a window left to inherit drew the sidebar's text in the wrong ink where it was drawn offscreen.
    private func followAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.applyAppearance() }
        }
    }

    private func applyAppearance() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        window?.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }

    private func refresh() {
        content.defaults.refresh(switches)
        if presenter.model.selection == .linkRules { content.links.rulesPane.model.reload() }
    }

    /// A menu item may have changed a setting the open window shows.
    @objc private func menuDidEndTracking(_ notification: Notification) {
        if window?.isVisible == true { refresh() }
    }

    /// The rules file may have been edited by hand while the window was in the background.
    func windowDidBecomeKey(_ notification: Notification) {
        refresh()
    }
}

private struct SettingsRootView: View {
    let model: SettingsShellModel<SettingsPaneID>
    let switches: DefaultsSummaryModel
    let content: SettingsContent

    var body: some View {
        SettingsShell(model, metrics: SettingsWindowController.metrics) { pane in
            Group {
                paneContent(pane)
            }
            .frame(height: SettingsWindowController.paneHeight, alignment: .top)
        }
        .theme(content.theme())
    }

    @ViewBuilder
    private func paneContent(_ pane: SettingsPaneID) -> some View {
        switch pane {
        case .general:
            GeneralPane(switches: switches, content: content)
        case .spaces:
            SpacesPane(registry: content.registry)
        case .shortcuts:
            ShortcutsSettingsView(shortcuts: content.shortcuts)
        case .defaults:
            DefaultsPaneView(model: switches, controller: content.defaults)
                .settingsPaneMargins()
        case .linkRules:
            LinkRulesSettingsPane(switches: switches, pane: content.links.rulesPane)
        case .sitePermissions:
            SitePermissionsPane(switches: switches, registry: content.registry)
        case .extensions:
            ExtensionsPane(registry: content.registry)
                .settingsPaneMargins()
        case .debug:
            DebugPane(switches: switches, diagnostics: content.diagnostics)
        }
    }
}

/// The switches a pane shows (`SettingsPaneID.switches`), each with its explanation, as the Defaults pane words them.
private struct PaneSwitches: View {
    let pane: SettingsPaneID
    let switches: DefaultsSummaryModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(pane.switches, id: \.self) { id in
                if let entry = switches.entries.first(where: { $0.id == id }) {
                    Toggle(isOn: Binding(get: { switches.isOn(id) }, set: { switches.setOn($0, for: id) })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                            Text(entry.explanation)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .help(entry.explanation)
                        }
                    }
                    .toggleStyle(.switch)
                    .accessibilityLabel(entry.title)
                    .accessibilityHint(entry.explanation)
                }
            }
        }
    }
}

private struct GeneralPane: View {
    let switches: DefaultsSummaryModel
    let content: SettingsContent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneSwitches(pane: .general, switches: switches)
            HStack {
                Spacer()
                Button(String(localized: "Check for Updates…", comment: "Menu item")) {
                    content.updates.checkForUpdates(nil)
                }
            }
            Divider()
            HStack {
                Text("Default browser", comment: "Settings, General pane: label of the default browser button")
                Spacer()
                let actions = content.defaults.defaultBrowserActions
                Button(actions.isDefault()
                       ? String(localized: "Safira Is the Default Browser", comment: "Disabled button: nothing left to do")
                       : String(localized: "Make Safira the Default Browser…", comment: "Button"),
                       action: actions.make)
                    .disabled(actions.isDefault())
            }
        }
        .settingsPaneMargins()
    }
}

/// The Active profile's Spaces in AppShellKit's list: drag to reorder (the Space rail's order, and ⌃1…⌃9's), "+" and
/// "−", Edit… opening the kit's editor, Delete with the kit's confirmation. It follows a switch to another Profile.
private struct SpacesPane: View {
    let registry: ProfileRegistry
    @State private var selection: SpaceID?
    @State private var editing: SpaceEditing?
    @State private var deleting: SpaceDeletion<SpaceID>?

    /// One opening of the editor, on a Space or on a new one.
    private struct SpaceEditing: Identifiable {
        let id = UUID()
        let space: SpaceID?
        let model: SpaceEditorModel
    }

    var body: some View {
        let session = registry.active.session
        VStack(alignment: .leading, spacing: 12) {
            Text("The Spaces of “\(registry.activeProfile.name)”, in the order of the Space rail. Drag one to change which ⌃1 to ⌃9 shows it. Deleting a Space closes its Tabs and Folders; the Profile’s logins and history are kept.",
                 comment: "Settings, Spaces pane; the argument is a Profile's name")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SpaceList(SpaceManagement.items(of: session), selection: $selection, palette: ThemeCatalog.palette,
                      deletion: { SpaceManagement.deletion(of: $0, in: session) },
                      perform: { action in SpaceManagement.perform(action, in: session) { open($0, in: session) } })
                .scrollContentBackground(.hidden)
                .padding(.horizontal, DesignTokens.Spacing.s)
                .settingsGroup()
        }
        .settingsPaneMargins()
        .sheet(item: $editing) { target in
            SpaceEditor(model: target.model) { result in
                if let saved = SpaceManagement.apply(result, editing: target.space, in: session) { selection = saved }
                if result == .deleteRequested, let id = target.space {
                    deleting = SpaceManagement.deletion(of: id, in: session)
                }
            }
            .theme(ThemeCatalog.theme(id: target.model.draft.themeID, fallback: ThemeCatalog.first))
        }
        .spaceDeletionConfirmation($deleting, palette: ThemeCatalog.palette) { id, _ in session.deleteSpace(id) }
    }

    private func open(_ id: SpaceID?, in session: ProfileSession) {
        if let id {
            guard let model = SpaceManagement.editor(editing: id, in: session) else { return }
            editing = SpaceEditing(space: id, model: model)
        } else {
            editing = SpaceEditing(space: nil, model: SpaceManagement.editorForNewSpace(in: session))
        }
    }
}

private struct LinkRulesSettingsPane: View {
    let switches: DefaultsSummaryModel
    let pane: LinkRulesPane

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneSwitches(pane: .linkRules, switches: switches)
            Divider()
            LinkRulesView(model: pane.model, actions: pane.actions)
        }
        .settingsPaneMargins()
    }
}

/// The Active profile's web content switches and remembered choices; it follows a switch to another Profile.
private struct SitePermissionsPane: View {
    let switches: DefaultsSummaryModel
    let registry: ProfileRegistry

    var body: some View {
        let name = registry.activeProfile.name
        VStack(alignment: .leading, spacing: 16) {
            PaneSwitches(pane: .sitePermissions, switches: switches)
            Text("These switches apply to “\(name)”, and to pages opened from now on.",
                 comment: "Settings, Site Permissions pane; the argument is a Profile's name")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            SitePermissionsView(profileName: name, permissions: registry.active.permissions)
        }
        .settingsPaneMargins()
    }
}

private struct DebugPane: View {
    let switches: DefaultsSummaryModel
    let diagnostics: DiagnosticsController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneSwitches(pane: .debug, switches: switches)
            HStack {
                Spacer()
                Button(String(localized: "Export Diagnostic Logs…", comment: "Menu item")) {
                    diagnostics.exportDiagnosticLogs(nil)
                }
            }
        }
        .settingsPaneMargins()
    }
}

private extension View {
    /// A pane that is not a grouped `Form`: on the header's margin, from the top.
    func settingsPaneMargins() -> some View {
        padding([.horizontal, .bottom], SettingsWindowController.metrics.paneMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
