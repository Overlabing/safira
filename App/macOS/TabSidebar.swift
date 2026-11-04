// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import ColorCore
import ColorUI
import DesignKit
import SafiraCore
import SafiraSession
import SafiraWeb
import SwiftUI

/// The Main window's column, from top to bottom: the address and Back, Forward and Reload; the active Space's name;
/// its pinned area with its Folders; a hairline; the New Tab row and the other Tabs; the Space switcher; the Active
/// profile's band. Arrow keys in the list move the selection, which shows the Tab; Delete closes it; Return or Escape
/// goes to its page. Tabs can be dragged to reorder, and Pinned tabs and Folders into Folders.
struct TabSidebar: View {
    let registry: ProfileRegistry
    let focus: ColumnFocus
    let pageActions: PageActions
    let profileActions: ProfileActions
    let spaceActions: SpaceActions
    let folderActions: FolderActions
    let newTabShortcut: () -> String?
    @Environment(\.designTokens) private var tokens

    private var session: ProfileSession { registry.active.session }

    var body: some View {
        VStack(spacing: 0) {
            BrowserControls(session: session, actions: pageActions)
            ScrollView {
                VStack(spacing: 0) {
                    SectionHeader(String(localized: "\(session.activeSpace.emoji) \(session.activeSpace.name)"),
                                  isGroupHeader: true)
                        .accessibilityLabel(String(localized: "Space: \(session.activeSpace.name)"))
                    PinnedSection(session: session, focus: focus, actions: folderActions)
                    if !session.pinnedItems.isEmpty { ColumnSeparator() }
                    NewTabRow(shortcut: newTabShortcut(), newTab: pageActions.newTab)
                    ForEach(Array(session.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabRowView(tab: tab, isSelected: session.selectedTabID == tab.id,
                                   isListFocused: focus.isListFocused, placement: .free(firstInSection: false),
                                   position: session.activeSpace.pinnedTabs.count + index + 1,
                                   count: session.activeSpace.allTabs.count,
                                   select: { session.select(tab.id) }, close: { session.close(tab.id) })
                            .modifier(TabDrag(tab: tab, session: session))
                            .contextMenu { TabMenu(tab: tab, session: session) }
                    }
                }
                .modifier(TabListKeyboard(session: session, focus: focus, showPage: pageActions.showPage))
            }
            .scrollContentBackground(.hidden)
            SpaceSwitcher(session: session, actions: spaceActions)
            ProfileBar(registry: registry, profileActions: profileActions, spaceActions: spaceActions)
        }
        .theme(spaceTheme)
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
        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab") { session.togglePin(tab.id) }
        Divider()
        Button("Move Up") { session.move(tab.id, by: -1) }
            .disabled(!session.canMove(tab.id, by: -1))
        Button("Move Down") { session.move(tab.id, by: 1) }
            .disabled(!session.canMove(tab.id, by: 1))
        Divider()
        Button("Close Tab") { session.close(tab.id) }
    }
}

/// The Space switcher: ThemeKit's glass bar of the Profile's Spaces, each its initial on its Theme's colour and the
/// active one named; absent with one Space. The emoji stays in the Space header: a glyph that shows it would show it
/// twice next to the name. Its context menu renames, moves or deletes the active Space.
private struct SpaceSwitcher: View {
    let session: ProfileSession
    let actions: SpaceActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let profileTheme = ThemeCatalog.first
        GlassSwitcher(
            session.spaces.map { space in
                SwitcherItem(id: space.id.rawValue.uuidString, name: space.name,
                             theme: ThemeCatalog.theme(id: space.paletteID, fallback: profileTheme))
            },
            selection: session.activeSpaceID.rawValue.uuidString,
            label: String(localized: "Spaces")
        ) { id in
            guard let space = session.spaces.first(where: { $0.id.rawValue.uuidString == id }) else { return }
            withAnimation(MotionRole.themeChange.animation(reduceMotion: reduceMotion)) {
                session.selectSpace(space.id)
            }
        }
        .contextMenu {
            Button("Rename Space…") { actions.edit(session.activeSpaceID) }
            Divider()
            Button("Move Left") { session.moveSpace(session.activeSpaceID, by: -1) }
                .disabled(session.spaces.first?.id == session.activeSpaceID)
            Button("Move Right") { session.moveSpace(session.activeSpaceID, by: 1) }
                .disabled(session.spaces.last?.id == session.activeSpaceID)
            Divider()
            Button("Delete Space…") { actions.delete(session.activeSpaceID) }
                .disabled(!session.canDeleteSpace)
        }
    }
}

/// The Active profile's band, a menu that switches Profile, and the button that adds a Space. It sits at the other end
/// of the column from the address, apart from the Space switcher's glass, so that a Profile never changes by accident.
private struct ProfileBar: View {
    let registry: ProfileRegistry
    let profileActions: ProfileActions
    let spaceActions: SpaceActions
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let profile = registry.activeProfile
        HStack(spacing: tokens.spacing.pillActionGap) {
            Menu {
                ForEach(registry.profiles) { item in
                    Toggle(isOn: Binding(get: { registry.activeProfileID == item.id },
                                         set: { if $0 { profileActions.select(item.id) } })) {
                        Text(verbatim: "\(item.symbol) \(item.name)")
                    }
                }
                Divider()
                Button("New Profile…") { profileActions.edit(nil) }
                Button("Rename Profile…") { profileActions.edit(registry.activeProfileID) }
                Button("Delete Profile…") { profileActions.delete(registry.activeProfileID) }
                    .disabled(!registry.canDeleteProfile)
                Divider()
                Button("Clear History and Website Data…") { profileActions.clearBrowsingData(registry.activeProfileID) }
            } label: {
                ThemeBand {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Text(verbatim: "\(profile.symbol) \(profile.name)")
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(tokens.type.accessory.font)
                            .accessibilityHidden(true)
                    }
                }
                .theme(ThemeCatalog.theme(id: profile.paletteID, fallback: ThemeCatalog.first))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help("Switch Profile")
            .accessibilityLabel(String(localized: "Profile: \(profile.name)"))
            .accessibilityHint("Opens the list of Profiles")
            IconButton(String(localized: "New Space"), systemImage: "plus") { spaceActions.edit(nil) }
        }
        .padding(.horizontal, tokens.spacing.listMargin)
        .padding(.bottom, tokens.spacing.switcherBottom)
    }
}

/// A Tab can be dragged before another one of its kind: a Pinned tab before a Pinned tab or into a Folder, a plain Tab
/// before a plain Tab. A drop that does not parse is refused, so text dragged in from elsewhere does nothing.
struct TabDrag: ViewModifier {
    let tab: SafiraSession.Tab
    let session: ProfileSession

    func body(content: Content) -> some View {
        content
            .draggable(PinnedDrag.text(for: .tab(tab.id)))
            .dropDestination(for: String.self) { texts, _ in
                guard let item = texts.first.flatMap(PinnedDrag.item(from:)) else { return false }
                if tab.isPinned { return session.movePinned(item, before: .tab(tab.id)) }
                guard case .tab(let dragged) = item, let index = session.tabs.firstIndex(where: { $0.id == tab.id }),
                      session.tabs.contains(where: { $0.id == dragged }) else { return false }
                session.move(dragged, to: index)
                return true
            }
    }
}
