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

/// What Settings' panes draw: the controllers that hold each setting.
struct SettingsContent {
    let registry: ProfileRegistry
    let defaults: DefaultsController
    let links: LinkController
    let shortcuts: ShortcutController
    let updates: UpdateController
    let diagnostics: DiagnosticsController
}

/// Settings in one window, on ThemeKit's sidebar swap: the window's column gives way to the panes under "This Profile"
/// and "Safira" (only "Safira" in a Private window), and its card to the pane shown. The page stays in the window under
/// the pane and comes back as it was. Safira › Settings… (⌘,) and the menu's other Settings items open it, and the
/// same item again, the back arrow or Escape returns.
@MainActor
final class SettingsHost {
    let swap: SettingsSwap
    /// The window's Profiles to switch between; nil in a Private window.
    private let registry: ProfileRegistry?
    private let theme: () -> Theme
    /// Given once the app's controllers exist, which is after the window: until then Settings does not open.
    private var content: SettingsContent?
    /// The switches of every pane, read again whenever the menu, another window or a Profile switch may have changed them.
    private var switches: DefaultsSummaryModel?
    private var paneHost: NSView?
    private weak var canvas: PageCanvasView?
    private var shownPresented = false

    /// Before the pane shows: the window puts away what floats over its page and shows its column.
    var willShow: (() -> Void)?
    /// After the pane went: the window gives the keyboard back to its page.
    var didHide: (() -> Void)?

    init(isPrivate: Bool, registry: ProfileRegistry?, theme: @escaping () -> Theme) {
        swap = SettingsSwap(isPrivate: isPrivate)
        self.registry = registry
        self.theme = theme
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { if self?.swap.isPresented == true { self?.refresh() } }
        }
    }

    var isPresented: Bool { swap.isPresented }

    /// The controllers the panes draw, and the card the panes take the place of; from then on the host follows the swap.
    func attach(_ content: SettingsContent, to canvas: PageCanvasView) {
        self.content = content
        self.canvas = canvas
        follow()
    }

    /// The action of every menu item that opens Settings; the item's `representedObject` names its `SettingsOpener`.
    func open(from sender: Any?) {
        guard content != nil else { return }
        let opener = ((sender as? NSMenuItem)?.representedObject as? String).flatMap(SettingsOpener.init(rawValue:))
        swap.open(opener ?? .settings)
    }

    func open(pane: SettingsPaneID) {
        guard content != nil else { return }
        swap.open(pane: pane)
    }

    func close() {
        swap.close()
    }

    /// The window's column while Settings is shown. `selectProfile` switches the window's Profile; nil in a Private
    /// window, which lists none of its Profile's panes.
    func column(sidebarShortcut: @escaping () -> String?, selectProfile: ((ProfileID) -> Void)?) -> SettingsColumn {
        SettingsColumn(model: swap.model, registry: registry, sidebarShortcut: sidebarShortcut,
                       selectProfile: selectProfile.map { select in
                           { [weak self] id in
                               select(id)
                               self?.refresh()
                           }
                       },
                       theme: theme)
    }

    /// Reads the switches again: the menu, another window or a Profile switch may have changed them.
    func refresh() {
        guard let content, let switches else { return }
        content.defaults.refresh(switches)
        if swap.pane == .linkRules { content.links.rulesPane.model.reload() }
    }

    private func follow() {
        let presented = withObservationTracking {
            swap.model.isPresented
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
        apply(presented)
    }

    private func apply(_ presented: Bool) {
        guard presented != shownPresented, let content else { return }
        shownPresented = presented
        if presented {
            let pane = paneHost ?? makePaneHost(content)
            refresh()
            willShow?()
            canvas?.showPane(pane)
            pane.window?.makeFirstResponder(pane)
        } else {
            canvas?.showPane(nil)
            didHide?()
        }
    }

    private func makePaneHost(_ content: SettingsContent) -> NSView {
        let switches = content.defaults.makeSummaryModel()
        self.switches = switches
        let host = NSHostingView(rootView: SettingsPaneRoot(swap: swap, switches: switches, content: content, theme: theme))
        paneHost = host
        return host
    }
}

/// The column of Settings: ThemeKit's section list, titled Settings, with the window's Profile in a menu under the
/// title, to switch Profile without leaving Settings.
struct SettingsColumn: View {
    let model: SidebarSwapModel<SettingsPaneID>
    let registry: ProfileRegistry?
    /// The shortcut the sidebar button's help tag names, in the bindings in force.
    let sidebarShortcut: () -> String?
    let selectProfile: ((ProfileID) -> Void)?
    let theme: () -> Theme

    var body: some View {
        SidebarSwapList(model, title: String(localized: "Settings", comment: "Settings: the title of the column"),
                        sidebarButtonShortcut: sidebarShortcut()) {
            EmptyView()
        } header: {
            if let registry, let selectProfile {
                ProfilePicker(registry: registry, select: selectProfile)
            }
        }
        .theme(theme())
    }
}

/// The window's Profile, named, with the others in its menu: choosing one shows it in the window, Settings staying open.
private struct ProfilePicker: View {
    let registry: ProfileRegistry
    let select: (ProfileID) -> Void

    var body: some View {
        Picker(String(localized: "Profile", comment: "Settings: label of the menu of the window's Profile"),
               selection: Binding(get: { registry.activeProfileID }, set: { select($0) })) {
            ForEach(registry.profiles) { profile in
                Text(verbatim: "\(profile.symbol)  \(profile.name)").tag(profile.id)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityHint(Text("The panes under This Profile change this Profile's settings.",
                                comment: "Settings: VoiceOver hint of the menu of the window's Profile"))
    }
}

/// The pane shown, in ThemeKit's pane: its title and subtitle, then the pane's own content.
private struct SettingsPaneRoot: View {
    let swap: SettingsSwap
    let switches: DefaultsSummaryModel
    let content: SettingsContent
    let theme: () -> Theme

    var body: some View {
        let pane = swap.model.selection
        SidebarSwapPane(swap.model) {
            paneContent(pane)
        }
        .id(pane)
        .theme(theme())
    }

    @ViewBuilder
    private func paneContent(_ pane: SettingsPaneID) -> some View {
        switch pane {
        case .searchEngine:
            SearchEnginePane(registry: content.registry)
        case .cookiePrompts:
            CookiePromptsPane(switches: switches, registry: content.registry)
        case .sitePermissions:
            SitePermissionsPane(switches: switches, registry: content.registry)
        case .spaces:
            SpacesPane(registry: content.registry)
        case .profileExtensions:
            ProfileExtensionsPane(registry: content.registry) { swap.open(pane: .extensions) }
                .settingsPaneMargins()
        case .general:
            GeneralPane(switches: switches, content: content)
        case .shortcuts:
            ShortcutsSettingsView(shortcuts: content.shortcuts)
        case .linkRules:
            LinkRulesSettingsPane(switches: switches, pane: content.links.rulesPane)
        case .extensions:
            ExtensionsPane(registry: content.registry)
                .settingsPaneMargins()
        case .defaults:
            DefaultsPaneView(model: switches, controller: content.defaults)
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
                        // Full width, so every switch of the pane lines up on the trailing edge.
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.switch)
                    .accessibilityLabel(entry.title)
                    .accessibilityHint(entry.explanation)
                }
            }
        }
    }
}

/// The search engine of the window's Profile. Nothing is preselected: a Profile that skipped the choice shows none.
private struct SearchEnginePane: View {
    let registry: ProfileRegistry

    var body: some View {
        let session = registry.active.session
        VStack(alignment: .leading, spacing: 16) {
            Picker(String(localized: "Search engine", comment: "Settings, Search Engine pane: label of the choice"),
                   selection: Binding(get: { session.settings.searchEngine },
                                      set: { if let engine = $0 { session.chooseSearchEngine(engine) } })) {
                ForEach(SearchEngine.allCases, id: \.self) { engine in
                    Text(verbatim: engine.name).tag(Optional(engine))
                }
            }
            .pickerStyle(.radioGroup)
            Text("Searches typed in the Command bar of “\(registry.activeProfile.name)” go to this engine. Each Profile has its own.",
                 comment: "Settings, Search Engine pane; the argument is a Profile's name")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .settingsPaneMargins()
    }
}

/// The window's Profile's cookie prompt switch and the sites where prompts are left alone.
private struct CookiePromptsPane: View {
    let switches: DefaultsSummaryModel
    let registry: ProfileRegistry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PaneSwitches(pane: .cookiePrompts, switches: switches)
                Text("This switch applies to “\(registry.activeProfile.name)”, and to pages opened from now on.",
                     comment: "Settings, Cookie Prompts pane; the argument is a Profile's name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
                CookiePromptExceptionsView(profile: registry.active)
            }
            .settingsPaneMargins()
        }
        .settingsScrollEdges()
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

/// The window's Profile's web content switches and remembered choices; it follows a switch to another Profile.
private struct SitePermissionsPane: View {
    let switches: DefaultsSummaryModel
    let registry: ProfileRegistry

    var body: some View {
        let name = registry.activeProfile.name
        // Two switches and a list can be taller than the window: the pane scrolls.
        ScrollView {
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
        .settingsScrollEdges()
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
        // The rules file may have been edited by hand since the pane last showed.
        .onAppear { pane.model.reload() }
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

extension View {
    /// A pane that is not a grouped `Form`: on the pane head's margin, from the top.
    func settingsPaneMargins() -> some View {
        padding([.horizontal, .bottom], DesignTokens.standard.spacing.swapPaneMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A pane that is a grouped `Form`: its sections on the pane head's margin, no background of its own. A grouped
    /// `Form` keeps a 20 pt margin of its own on macOS, taken off here.
    func settingsFormLayout() -> some View {
        let margin = DesignTokens.standard.spacing.swapPaneMargin
        return formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, margin - 20, for: .scrollContent)
            .contentMargins(.bottom, margin, for: .scrollContent)
    }
}
