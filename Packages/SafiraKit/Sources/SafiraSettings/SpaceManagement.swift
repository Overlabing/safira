// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppShellKit
import Appearance
import Foundation
import SafiraCore
import SafiraSession
import Spaces

/// A Profile's Spaces through AppShellKit's Space editor, Space list and deletion confirmation: what the kit shows is
/// read from the Profile's session, and what the kit sends back is applied to it. The Settings pane and the Main
/// window (the Space rail's menus, the Spaces menu) go through here alike.
@MainActor
public enum SpaceManagement {
    /// The Profile's Spaces for the kit's list, in the order of the Space rail and of ⌃1…⌃9.
    public static func items(of session: ProfileSession) -> [SpaceListItem<SpaceID>] {
        session.spaces.map { space in
            SpaceListItem(
                id: space.id, name: space.name, icon: space.icon, themeID: themeID(of: space),
                detail: tabCount(space.allTabs.count),
                note: space.id == session.activeSpaceID
                    ? String(localized: "Shown", table: "SafiraSettings", bundle: .module,
                             comment: "Settings, Spaces pane: note of the Space the Main window shows")
                    : nil)
        }
    }

    /// The editor of a new Space: a free name, the initial of the name as its icon, and the first Theme no other Space
    /// of the Profile wears.
    public static func editorForNewSpace(in session: ProfileSession) -> SpaceEditorModel {
        let names = session.spaces.map(\.name)
        let number = ((names.count + 1)...).first { number in
            !names.contains { $0.caseInsensitiveCompare(defaultName(number)) == .orderedSame }
        } ?? names.count + 1
        let draft = SpaceDraft(name: defaultName(number), icon: .initial,
                               themeID: ThemeCatalog.nextID(avoiding: session.spaces.map(\.paletteID)))
        return SpaceEditorModel(draft, purpose: .create, otherNames: names, palette: ThemeCatalog.palette)
    }

    /// The editor of the Space `id`; nil when the Profile has no such Space. It offers "Delete Space…" unless it is the
    /// Profile's last Space.
    public static func editor(editing id: SpaceID, in session: ProfileSession) -> SpaceEditorModel? {
        guard let space = session.spaces.first(where: { $0.id == id }) else { return nil }
        let draft = SpaceDraft(name: space.name, icon: space.icon, themeID: themeID(of: space))
        return SpaceEditorModel(draft, purpose: .edit, otherNames: session.spaces.filter { $0.id != id }.map(\.name),
                                palette: ThemeCatalog.palette, canDelete: session.canDeleteSpace)
    }

    /// Applies what the editor sent back: a saved draft creates the Space (`editing` nil), shown at once, or edits it.
    /// Returns the Space saved; nil for a cancel, a request to delete (the caller confirms it, `deletion(of:in:)`), or a
    /// name the Space rules refuse.
    @discardableResult
    public static func apply(_ result: SpaceEditorResult, editing id: SpaceID?,
                             in session: ProfileSession) -> SpaceID? {
        guard case .saved(let draft) = result else { return nil }
        do {
            guard let id else {
                return try session.createSpace(name: draft.name, icon: draft.icon, paletteID: draft.themeID)
            }
            try session.editSpace(id, name: draft.name, icon: draft.icon, paletteID: draft.themeID)
            return id
        } catch {
            return nil
        }
    }

    /// The confirmation of deleting the Space `id`; nil for the Profile's last Space, which is never deleted. Deleting a
    /// Space closes its Tabs and Folders, as it always has in Safira: nothing moves to another Space, so the kit shows a
    /// single Delete button with Safira's words.
    public static func deletion(of id: SpaceID, in session: ProfileSession) -> SpaceDeletion<SpaceID>? {
        guard session.canDeleteSpace, let space = session.spaces.first(where: { $0.id == id }) else { return nil }
        let count = space.allTabs.count
        let tabs = count == 0
            ? String(localized: "It has no Tab.", table: "SafiraSettings", bundle: .module,
                     comment: "Delete Space confirmation: the Space holds no Tab")
            : String(localized: "Its \(count) Tabs will close.", table: "SafiraSettings", bundle: .module,
                     comment: "Delete Space confirmation; a count of Tabs, at least 1")
        let kept = String(localized: "The Profile's logins and history are kept.", table: "SafiraSettings",
                          bundle: .module, comment: "Delete Space confirmation")
        return SpaceDeletion(deleting: id, in: items(of: session), defaultSpace: nil, contentCount: 0,
                             message: tabs + " " + kept)
    }

    /// Performs what the kit's list asked: `edit` opens the editor (nil for a new Space), a new order becomes the rail's
    /// and ⌃1…⌃9's, a confirmed deletion deletes the Space with its Tabs.
    public static func perform(_ action: SpaceListAction<SpaceID>, in session: ProfileSession,
                               edit: (SpaceID?) -> Void) {
        switch action {
        case .create: edit(nil)
        case .edit(let id): edit(id)
        case .reorder(let order): session.reorderSpaces(order)
        case .delete(let id, _): session.deleteSpace(id)
        }
    }

    private static func themeID(of space: Space) -> String {
        space.paletteID ?? ThemeCatalog.first.id
    }

    private static func defaultName(_ number: Int) -> String {
        String(localized: "Space \(number)", table: "SafiraSettings", bundle: .module,
               comment: "Name proposed for a new Space; the number follows the Profile's Spaces")
    }

    private static func tabCount(_ count: Int) -> String {
        String(localized: "\(count) Tabs", table: "SafiraSettings", bundle: .module,
               comment: "Settings, Spaces pane: under a Space's name, how many Tabs it holds")
    }
}
