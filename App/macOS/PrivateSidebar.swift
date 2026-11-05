// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import ColorUI
import DesignKit
import SafiraCore
import SafiraSession
import SwiftUI

/// The column of a Private window, ThemeKit's sidebar column like the Main window's: the address and Back, Forward and
/// Reload in the head field, the list of its Tabs, and in the bottom bar, where the Main window has the Space rail, a
/// band naming the Profile it is attached to. The Private Theme's purple, always dark, is what tells it from the Main
/// window.
struct PrivateSidebar: View {
    let session: ProfileSession
    let parent: Profile
    let focus: ColumnFocus
    let pageActions: PageActions
    @Environment(\.designTokens) private var tokens

    var body: some View {
        List {
            NewTabRow(shortcut: nil, newTab: pageActions.newTab)
            ForEach(Array(session.tabs.enumerated()), id: \.element.id) { index, tab in
                TabRowView(tab: tab, icons: session.siteIcons, isSelected: session.selectedTabID == tab.id,
                           isListFocused: focus.isListFocused, placement: .free,
                           position: index + 1, count: session.tabs.count,
                           select: { session.select(tab.id) }, close: { session.close(tab.id) })
                    .modifier(TabDrag(tab: tab, session: session))
                    .contextMenu {
                        Button("Move Up") { session.move(tab.id, by: -1) }
                            .disabled(index == 0)
                        Button("Move Down") { session.move(tab.id, by: 1) }
                            .disabled(index == session.tabs.count - 1)
                        Divider()
                        Button("Close Tab") { session.close(tab.id) }
                    }
            }
        }
        .modifier(TabListKeyboard(session: session, focus: focus, showPage: pageActions.showPage))
        .sidebarColumn {
            BrowserControls(session: session, actions: pageActions)
        } header: {
            EmptyView()
        } bottomBar: {
            ThemeBand {
                Label(String(localized: "Private · \(parent.symbol) \(parent.name)", comment: "Private window sidebar"), systemImage: "eye.slash.fill")
            }
            .padding(.horizontal, tokens.spacing.listMargin)
            .padding(.bottom, tokens.spacing.switcherBottom)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(String(localized: "Private window, attached to the Profile \(parent.name). Nothing is saved.", comment: "Private window sidebar"))
        }
        .theme(SidebarComposition.privateTheme)
        .environment(\.colorScheme, .dark)
    }
}
