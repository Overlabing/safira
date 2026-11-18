// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Appearance
import AppShellKit
import ColorCore
import Commands
import DesignKit
import DownloadsUI
import Onboarding
import Preferences
import SafiraCore
import SafiraSession
import SafiraSettings
import SafiraWeb
import SwiftUI

/// What Settings' panes draw: the controllers that hold each setting.
/// What the Library's items draw: the controllers that hold each setting.
struct SettingsContent {
    let registry: ProfileRegistry
    let defaults: DefaultsController
    let links: LinkController
    let shortcuts: ShortcutController
    let updates: UpdateController
    let diagnostics: DiagnosticsController
}

/// The downloads a window's Library lists: its Profile's, or a Private window's own.
struct LibraryDownloads {
    let downloads: () -> ProfileDownloads
    let web: () -> ProfileWebContext
}

/// The Library in one window, as in Zen: the sidebar gives way to a rail (Downloads, Spaces, Link Rules, Extensions,
/// Settings), the chosen item's content is drawn on the window's own chrome, and the page's card is pushed toward the
/// trailing edge with a strip of it in sight. The page stays in the window and comes back as it was. ⌘, opens it on
/// Settings, ⌥⌘L on Downloads; the rail's ←, Escape, ⌘[, the mouse's back button, a swipe back, or a click on the page
/// left in sight close it.
@MainActor
final class LibraryHost {
    let navigation: LibraryNavigation
    private let downloads: LibraryDownloads
    private let theme: () -> Theme
    /// What the page's title is, for the back hint and the announcement on closing; nil with no page.
    private let pageTitle: () -> String?
    /// Given once the app's controllers exist, which is after the window: until then the Library does not open.
    private var content: SettingsContent?
    private var switches: DefaultsSummaryModel?
    private var host: NSView?
    private weak var layout: BrowserWindowLayout?
    private weak var canvas: PageCanvasView?
    private var shownPresented = false

    /// After the Library opened: the window puts away what floats over its page.
    var didShow: (() -> Void)?
    /// After it closed: the window gives the keyboard back to its page.
    var didHide: (() -> Void)?

    init(isPrivate: Bool, downloads: LibraryDownloads, theme: @escaping () -> Theme,
         pageTitle: @escaping () -> String?) {
        navigation = LibraryNavigation(isPrivate: isPrivate)
        self.downloads = downloads
        self.theme = theme
        self.pageTitle = pageTitle
        NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { if self?.navigation.isPresented == true { self?.refresh() } }
        }
    }

    var isPresented: Bool { navigation.isPresented }

    /// The controllers the items draw, and the window the Library opens in; from then on the host follows it.
    func attach(_ content: SettingsContent, to layout: BrowserWindowLayout, canvas: PageCanvasView) {
        self.content = content
        self.layout = layout
        self.canvas = canvas
        follow()
    }

    /// The action of every menu item that opens Settings; the item's `representedObject` names its `SettingsOpener`.
    func open(from sender: Any?) {
        let opener = ((sender as? NSMenuItem)?.representedObject as? String).flatMap(SettingsOpener.init(rawValue:))
        toggle((opener ?? .settings).destination)
    }

    func toggle(_ destination: LibraryDestination) {
        guard content != nil else { return }
        navigation.toggle(destination)
    }

    func open(_ destination: LibraryDestination) {
        guard content != nil else { return }
        navigation.open(destination)
    }

    func close() {
        navigation.close()
    }

    /// "Back to <page>", or "Back to browsing" with no page.
    var backTitle: String {
        if let title = pageTitle(), !title.isEmpty {
            return String(localized: "Back to \(title)", comment: "Library: the way back to the page, for VoiceOver; the argument is the page's title")
        }
        return String(localized: "Back to browsing", comment: "Library: the way back when no page is open")
    }

    /// Reads the switches again: the menu, another window or a Profile switch may have changed them.
    func refresh() {
        guard let content, let switches else { return }
        content.defaults.refresh(switches)
        if navigation.item == .linkRules { content.links.rulesPane.model.reload() }
    }

    private func follow() {
        let presented = withObservationTracking {
            navigation.rail.isPresented
        } onChange: { [weak self] in
            Task { @MainActor in self?.follow() }
        }
        apply(presented)
    }

    private func apply(_ presented: Bool) {
        guard presented != shownPresented, let content, let layout, let canvas else { return }
        shownPresented = presented
        if presented {
            let host = host ?? makeHost(content)
            refresh()
            layout.showLibrary(host, animated: true)
            canvas.showPeek(label: backTitle, hint: String(localized: "Click the page to go back", comment: "Library: the hint on the page pushed aside")) {
                [weak self] in self?.close()
            }
            host.window?.makeFirstResponder(host)
            announce(String(localized: "Library, \(navigation.rail.current.title)", comment: "Library: announced when it opens; the argument is the item shown"))
            didShow?()
        } else {
            let title = backTitle
            canvas.showPeek(label: nil)
            layout.hideLibrary(animated: true)
            didHide?()
            announce(title)
        }
    }

    private func announce(_ message: String) {
        guard let window = layout?.view.window else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func makeHost(_ content: SettingsContent) -> NSView {
        let switches = content.defaults.makeSummaryModel(isPrivate: navigation.isPrivate)
        self.switches = switches
        let host = NSHostingView(rootView: LibraryRoot(
            navigation: navigation, switches: switches, content: content, downloads: downloads, theme: theme,
            selectProfile: navigation.isPrivate ? nil : { [weak self] id in
                content.registry.selectProfile(id)
                self?.refresh()
            }))
        self.host = host
        return host
    }
}

/// The Library's view: the rail, then the item's content, on the window's chrome.
private struct LibraryRoot: View {
    let navigation: LibraryNavigation
    let switches: DefaultsSummaryModel
    let content: SettingsContent
    let downloads: LibraryDownloads
    let theme: () -> Theme
    let selectProfile: ((ProfileID) -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            LibraryRail(navigation.rail, title: String(localized: "Library", comment: "Library: VoiceOver name of the rail"))
            itemContent(navigation.item)
                .id(navigation.item)
        }
        .theme(theme())
    }

    @ViewBuilder
    private func itemContent(_ item: LibraryItemID) -> some View {
        let info = SafiraSettings.item(item)
        switch item {
        case .settings:
            SettingsLibraryItem(navigation: navigation, switches: switches, content: content, selectProfile: selectProfile)
        case .downloads:
            LibraryPane(title: info.title, subtitle: SafiraSettings.subtitle(of: item), onExit: navigation.close) {
                LibraryDownloadsList(downloads: downloads)
                    .settingsPaneMargins()
            }
        case .spaces:
            LibraryPane(title: info.title, subtitle: SafiraSettings.subtitle(of: item), onExit: navigation.close) {
                SpacesPane(registry: content.registry)
            }
        case .linkRules:
            LibraryPane(title: info.title, subtitle: SafiraSettings.subtitle(of: item), onExit: navigation.close) {
                LinkRulesSettingsPane(switches: switches, pane: content.links.rulesPane)
            }
        case .extensions:
            LibraryPane(title: info.title, subtitle: SafiraSettings.subtitle(of: item), onExit: navigation.close) {
                ExtensionsPane(registry: content.registry)
                    .settingsPaneMargins()
            }
        }
    }
}

/// Settings in the Library: the list of its panes under This Profile and Safira, the window's Profile in a menu above
/// them, and the pane shown beside it, both on the window's chrome.
private struct SettingsLibraryItem: View {
    let navigation: LibraryNavigation
    let switches: DefaultsSummaryModel
    let content: SettingsContent
    let selectProfile: ((ProfileID) -> Void)?
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let pane = SafiraSettings.pane(navigation.settingsPane)
        HStack(spacing: 0) {
            SettingsList(navigation: navigation, registry: content.registry, selectProfile: selectProfile)
                .frame(width: SafiraDesign.settingsListWidth)
            LibraryPane(title: pane.title, subtitle: pane.subtitle, onExit: navigation.close) {
                paneContent(pane.id)
            }
            .id(pane.id)
        }
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
        case .general:
            GeneralPane(switches: switches, content: content)
        case .shortcuts:
            ShortcutsSettingsView(shortcuts: content.shortcuts)
        case .defaults:
            DefaultsPaneView(model: switches, controller: content.defaults, isPrivate: navigation.isPrivate)
                .settingsPaneMargins()
        case .debug:
            DebugPane(switches: switches, diagnostics: content.diagnostics)
        case .spaces, .linkRules, .extensions:
            EmptyView()
        }
    }
}

/// The list of Settings' panes, under This Profile and Safira, with the window's Profile in a menu above This Profile.
/// Up and Down move between the panes, which show at once.
private struct SettingsList: View {
    let navigation: LibraryNavigation
    let registry: ProfileRegistry
    let selectProfile: ((ProfileID) -> Void)?
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let selection = Binding<SettingsPaneID?>(get: { navigation.settingsPane },
                                                 set: { if let pane = $0 { navigation.select(pane: pane) } })
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s) {
            Text("Settings", comment: "Library: the title of Settings' list")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, tokens.spacing.listMargin)
            if let selectProfile {
                ProfilePicker(registry: registry, select: selectProfile)
                    .padding(.horizontal, tokens.spacing.listMargin)
            }
            List(selection: selection) {
                ForEach(SafiraSettings.groups(isPrivate: navigation.isPrivate)) { group in
                    Section(group.title) {
                        ForEach(group.panes) { pane in
                            Label(pane.title, systemImage: pane.systemImage)
                                .tag(pane.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .accessibilityLabel(Text("Settings", comment: "Library: the title of Settings' list"))
        }
        .padding(.top, tokens.size.sidebarTitleBar + DesignTokens.Spacing.s)
        .onExitCommand { navigation.close() }
    }
}

/// The window's Profile, named, with the others in its menu: choosing one shows it in the window, the Library staying
/// open, so This Profile's panes change it.
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

/// The window's downloads in the Library: the downloads panel, at the width of the pane.
private struct LibraryDownloadsList: View {
    let downloads: LibraryDownloads

    var body: some View {
        let list = downloads.downloads()
        let web = downloads.web()
        DownloadsPanel(downloads: list, folder: DownloadsFolder(
            url: list.savesInAppFolder ? web.downloadsFallbackDirectory : web.downloadsDirectory,
            isAppFolder: list.savesInAppFolder), layout: .library)
            // macOS asks for the Downloads folder the first time it is needed; asking here, when the user opened the
            // list, keeps that prompt from appearing in the middle of a page's download.
            .task { await web.prepareDownloadsAccess() }
            .settingsGroup()
    }
}

/// A group of rows in a pane, as in the mock: a translucent rounded box on the window's chrome.
struct SettingsBox<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .settingsGroup()
    }
}

private struct PaneSwitches: View {
    let pane: SettingsPaneID
    let switches: DefaultsSummaryModel

    var body: some View {
        SettingsBox {
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
            SettingsBox {
                Picker(String(localized: "Search engine", comment: "Settings, Search Engine pane: label of the choice"),
                       selection: Binding(get: { session.settings.searchEngine },
                                          set: { if let engine = $0 { session.chooseSearchEngine(engine) } })) {
                    ForEach(SearchEngine.allCases, id: \.self) { engine in
                        Text(verbatim: engine.name).tag(Optional(engine))
                    }
                }
                .pickerStyle(.radioGroup)
            }
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
            SettingsBox {
                HStack {
                    Text("Updates", comment: "Settings, General pane: label of the update button")
                    Spacer()
                    Button(String(localized: "Check for Updates…", comment: "Menu item")) {
                        content.updates.checkForUpdates(nil)
                    }
                }
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
            SettingsBox {
                HStack {
                    Text("Logs", comment: "Settings, Debug pane: label of the export button")
                    Spacer()
                    Button(String(localized: "Export Diagnostic Logs…", comment: "Menu item")) {
                        diagnostics.exportDiagnosticLogs(nil)
                    }
                }
            }
        }
        .settingsPaneMargins()
    }
}

extension View {
    /// A pane that is not a grouped `Form`: on the pane head's margin, from the top.
    func settingsPaneMargins() -> some View {
        padding([.horizontal, .bottom], DesignTokens.standard.spacing.libraryPaneMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A pane that is a grouped `Form`: its sections on the pane head's margin, no background of its own. A grouped
    /// `Form` keeps a 20 pt margin of its own on macOS, taken off here.
    func settingsFormLayout() -> some View {
        let margin = DesignTokens.standard.spacing.libraryPaneMargin
        return formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, margin - 20, for: .scrollContent)
            .contentMargins(.bottom, margin, for: .scrollContent)
    }
}

/// The Library's ways back that come as raw events: the mouse's back button, and a two-finger swipe back where the
/// user has turned swiping between pages on. A window offers them its events while its Library is open.
@MainActor
enum LibraryBackGesture {
    /// True when `event` was one of them, and `back` ran or will run when the swipe ends.
    static func handle(_ event: NSEvent, back: @escaping @MainActor () -> Void) -> Bool {
        switch event.type {
        case .otherMouseDown where event.buttonNumber == 3:
            back()
            return true
        case .scrollWheel where event.phase == .began && NSEvent.isSwipeTrackingFromScrollEventsEnabled
            && abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) && event.scrollingDeltaX > 0:
            event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount], dampenAmountThresholdMin: 0, max: 1) {
                amount, phase, _, _ in
                guard phase == .ended, amount >= 1 else { return }
                MainActor.assumeIsolated { back() }
            }
            return true
        default:
            return false
        }
    }
}
