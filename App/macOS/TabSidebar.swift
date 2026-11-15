// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import ColorCore
import ColorUI
import Commands
import DesignKit
import SafiraCore
import SafiraSession
import SafiraWeb
import SwiftUI

/// The Main window's column, ThemeKit's sidebar column (`sidebarColumn(field:header:bottomBar:)`): the address and
/// Back, Forward and Reload in the head field; a plain list of the active Space's pinned area with its Folders, a
/// hairline, the New Tab row and the other Tabs; the Space rail with the Spaces and Profiles in the bottom bar. Arrow
/// keys in the list move the selection, which shows the Tab; Delete closes it; Return or Escape goes to its page. A Tab
/// or Folder dragged onto the list lands where the insertion line shows it: a plain Tab dropped in the pinned area or a
/// Folder is pinned there, a Pinned tab dropped among the other Tabs is unpinned there (`ProfileSession.drop`).
struct TabSidebar: View {
    let registry: ProfileRegistry
    let focus: ColumnFocus
    let pageActions: PageActions
    let profileActions: ProfileActions
    let spaceActions: SpaceActions
    let folderActions: FolderActions
    /// The shortcut a menu item shows for a command, in the bindings in force ("⌘T", "⌃1").
    let shortcut: (CommandID) -> String?

    private var session: ProfileSession { registry.active.session }

    @State private var drag = SidebarDrag()

    var body: some View {
        List {
            PinnedSection(session: session, focus: focus, actions: folderActions, drag: drag)
            if !session.pinnedItems.isEmpty || drag.isDragging { SidebarSeparator() }
            NewTabRow(shortcut: shortcut(.newTab), isSelected: session.sidebarSelection == .newTab,
                      newTab: pageActions.newTab)
                .sidebarDropTarget(.gap(.tabs(index: 0)), row: "safira.newTabRow", drag: drag, session: session)
            ForEach(PlainTabCell.cells(of: session.tabs, line: drag.linePlace)) { cell in
                switch cell {
                case .tab(let tab, let index):
                    TabRowView(tab: tab, icons: session.siteIcons,
                               isSelected: session.sidebarSelection == .tab(tab.id),
                               isListFocused: focus.isListFocused, placement: .free,
                               position: session.activeSpace.pinnedTabs.count + index + 1,
                               count: session.activeSpace.allTabs.count,
                               select: { session.select(tab.id) }, close: { session.close(tab.id) })
                        .sidebarDragSource(.tab(tab.id), drag: drag)
                        .sidebarDropTarget(.row(above: .tabs(index: index), below: .tabs(index: index + 1)),
                                           row: cell.id, drag: drag, session: session)
                        .contextMenu { TabMenu(tab: tab, session: session) }
                case .line:
                    if let place = drag.linePlace {
                        InsertionLineRow(placement: .free)
                            .sidebarDropTarget(.gap(place), row: cell.id, drag: drag, session: session)
                    }
                }
            }
        }
        .modifier(TabListKeyboard(session: session, focus: focus, showPage: pageActions.showPage))
        .sidebarColumn {
            BrowserControls(session: session, actions: pageActions)
        } header: {
            EmptyView()
        } bottomBar: {
            SpaceRailBar(registry: registry, profileActions: profileActions, spaceActions: spaceActions,
                         shortcut: shortcut)
        }
        .theme(spaceTheme)
        #if DEBUG
        .task { await SidebarDragPreview.run(session: session, drag: drag) }
        #endif
    }

    /// The Space's Theme colours the column; a Space with none wears its Profile's.
    private var spaceTheme: Theme {
        let profile = ThemeCatalog.theme(id: registry.activeProfile.paletteID, fallback: ThemeCatalog.first)
        return ThemeCatalog.theme(id: session.activeSpace.paletteID, fallback: profile)
    }
}

/// The context menu of a Tab row.
struct TabMenu: View {
    let tab: SafiraSession.Tab
    let session: ProfileSession

    var body: some View {
        Button(tab.isPinned ? String(localized: "Unpin Tab", comment: "Tab context menu")
                            : String(localized: "Pin Tab", comment: "Tab context menu")) { session.togglePin(tab.id) }
        if tab.isAwayFromPinnedAddress {
            Button(String(localized: "Back to Pinned Address", comment: "Tab context menu")) {
                session.returnToPinnedAddress(tab.id)
            }
            Button(String(localized: "Replace Pinned Address with Current Page", comment: "Tab context menu")) {
                session.replacePinnedAddress(tab.id)
            }
        }
        Divider()
        Button("Move Up") { session.move(tab.id, by: -1) }
            .disabled(!session.canMove(tab.id, by: -1))
        Button("Move Down") { session.move(tab.id, by: 1) }
            .disabled(!session.canMove(tab.id, by: 1))
        Divider()
        Button("Close Tab") { session.close(tab.id) }
    }
}

/// The Space rail, ThemeKit's one selector at the bottom of the column: the Active profile's Spaces as glyphs, the
/// other Profiles folded into dots after a hairline, and a `+` with the commands that add or edit them. A click on a
/// folded Profile shows it on its last Space. A secondary click on a Space or a Profile opens that item's menu
/// (`SpaceRailMenu`), whichever is current; a command on a Profile that is not shown shows it first.
private struct SpaceRailBar: View {
    let registry: ProfileRegistry
    let profileActions: ProfileActions
    let spaceActions: SpaceActions
    let shortcut: (CommandID) -> String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Command: String {
        case newSpace, newProfile, editSpace, editProfile
    }

    private var session: ProfileSession { registry.active.session }

    var body: some View {
        let profile = registry.activeProfile
        let shortcuts = SpaceRailContent.Shortcuts(
            spaces: CommandID.selectSpaceCommands.map(shortcut),
            previousProfile: shortcut(.previousProfile), nextProfile: shortcut(.nextProfile))
        let profiles = SpaceRailContent.profiles(registry.profiles, activeID: registry.activeProfileID,
                                                 spaces: registry.spaceSummary(of:), shortcuts: shortcuts)
        SpaceRail(
            profiles: profiles,
            selection: session.activeSpaceID.rawValue.uuidString,
            commands: [
                [
                    SpaceRailCommand(id: Command.newSpace.rawValue,
                                     title: String(localized: "New Space in \(profile.name)…", comment: "Sidebar menu"), systemImage: "plus"),
                    SpaceRailCommand(id: Command.newProfile.rawValue, title: String(localized: "New Profile…", comment: "Sidebar menu"),
                                     systemImage: "person.crop.circle.badge.plus"),
                ],
                [
                    SpaceRailCommand(id: Command.editSpace.rawValue,
                                     title: String(localized: "Edit Space \(session.activeSpace.name)…", comment: "Sidebar menu"),
                                     systemImage: "pencil"),
                    SpaceRailCommand(id: Command.editProfile.rawValue,
                                     title: String(localized: "Edit Profile \(profile.name)…", comment: "Sidebar menu"),
                                     systemImage: "person.crop.circle"),
                ],
            ],
            selectSpace: selectSpace,
            selectProfile: { id in ProfileID(uuidString: id).map(profileActions.select) },
            perform: perform)
        .spaceRailContextMenu { space in
            RailMenu(sections: SpaceRailMenu.space(space.id, in: profiles)) { run($0, in: profiles) }
        } profile: { profile in
            RailMenu(sections: SpaceRailMenu.profile(profile.id, in: profiles)) { run($0, in: profiles) }
        }
    }

    /// A Space of the Active profile, or, from the "+n" panel, of another Profile: that Profile is shown first.
    private func selectSpace(_ id: String) {
        guard let space = SpaceID(uuidString: id) else { return }
        if !session.spaces.contains(where: { $0.id == space }),
           let owner = registry.profiles.first(where: { registry.spaceSummary(of: $0.id).spaces.contains { $0.id == space } }) {
            profileActions.select(owner.id)
        }
        withAnimation(MotionRole.themeChange.animation(reduceMotion: reduceMotion)) {
            session.selectSpace(space)
        }
    }

    /// A command of an item's menu, on the Space or Profile it names. A Profile that is not shown is shown first, so the
    /// result is visible (`SpaceRailMenu.Action.profileToShow`).
    private func run(_ action: SpaceRailMenu.Action, in profiles: [SpaceRailProfile]) {
        if let profile = action.profileToShow(in: profiles), profile != registry.activeProfileID {
            profileActions.select(profile)
        }
        switch action {
        case .editSpace(let id): spaceActions.edit(id)
        case .moveSpaceLeft(let id): registry.context(ofSpace: id)?.session.moveSpace(id, by: -1)
        case .moveSpaceRight(let id): registry.context(ofSpace: id)?.session.moveSpace(id, by: 1)
        case .deleteSpace(let id): spaceActions.delete(id)
        case .editProfile(let id): profileActions.edit(id)
        case .deleteProfile(let id): profileActions.delete(id)
        case .clearBrowsingData(let id): profileActions.clearBrowsingData(id)
        }
    }

    private func perform(_ id: String) {
        switch Command(rawValue: id) {
        case .newSpace: spaceActions.edit(nil)
        case .newProfile: profileActions.edit(nil)
        case .editSpace: spaceActions.edit(session.activeSpaceID)
        case .editProfile: profileActions.edit(registry.activeProfileID)
        case nil: break
        }
    }
}

/// A Space rail item's menu: its sections between dividers, each command under the title it had on the whole rail.
private struct RailMenu: View {
    let sections: [[SpaceRailMenu.Item]]
    let run: (SpaceRailMenu.Action) -> Void

    var body: some View {
        ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
            if index > 0 { Divider() }
            ForEach(section, id: \.self) { item in
                button(item.action).disabled(!item.isEnabled)
            }
        }
    }

    @ViewBuilder
    private func button(_ action: SpaceRailMenu.Action) -> some View {
        switch action {
        case .editSpace: Button("Edit Space…") { run(action) }
        case .moveSpaceLeft: Button("Move Space Left") { run(action) }
        case .moveSpaceRight: Button("Move Space Right") { run(action) }
        case .deleteSpace: Button("Delete Space…") { run(action) }
        case .editProfile: Button("Edit Profile…") { run(action) }
        case .deleteProfile: Button("Delete Profile…") { run(action) }
        case .clearBrowsingData: Button("Clear History and Website Data…") { run(action) }
        }
    }
}

#if DEBUG
/// Captures of the sidebar's drag and drop, which cannot drag in the background: the launch argument
/// `-SafiraDragPreview zone|line|drop` opens three Tabs, then shows the empty pinned area under a dragged Tab (`zone`),
/// pins the first Tab by a drop and shows the line where the third would land (`line`), or drops both (`drop`). Debug
/// builds only.
@MainActor
private enum SidebarDragPreview {
    static func run(session: ProfileSession, drag: SidebarDrag) async {
        guard let mode = UserDefaults.standard.string(forKey: "SafiraDragPreview") else { return }
        let ids = ["https://example.com", "https://example.org", "https://example.net"].compactMap(URL.init(string:))
            .map { session.openExternalLink($0) }
        try? await Task.sleep(for: .seconds(2))
        let first = PinnedItemID.tab(ids[0]), third = PinnedItemID.tab(ids[2])
        if mode != "zone" { session.drop(first, at: .pinned(folder: nil, index: 0)) }
        let place = SidebarDropPlace.pinned(folder: nil, index: mode == "zone" ? 0 : 1)
        if mode == "drop" {
            session.drop(third, at: place)
        } else {
            _ = drag.begin(third)
            drag.propose(SidebarDrag.Hover(place: place, row: "preview"))
        }
    }
}
#endif
