// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import LinkRouting
import Observation
import SafiraCore

/// One Profile, or one Space, offered by the Link picker.
public struct LinkPickerRow<ID: Hashable & Sendable>: Hashable, Identifiable, Sendable {
    public let id: ID
    /// The position shown to the user, starting at 1. Only 1 to 9 have a number key.
    public let number: Int
    public let symbol: String
    public let name: String
    /// Whether a Tab of this Profile already shows the link. It is a mark only: the row is not highlighted or chosen
    /// because of it.
    public let isLinkOpen: Bool

    public var numberKey: Character? {
        number <= 9 ? Character(String(number)) : nil
    }
}

/// What a key did to the Link picker.
public enum LinkPickerOutcome<ID: Hashable & Sendable>: Hashable, Sendable {
    case none
    case chose(ID)
    /// The user dismissed the question; the link is dropped.
    case cancelled
}

/// The state of the Link picker. Nothing is highlighted when it opens: a number key chooses a row at once, an arrow
/// key highlights one and Return then chooses the highlighted row. Return does nothing while no row is highlighted.
@MainActor
@Observable
public final class LinkPickerModel<ID: Hashable & Sendable> {
    public let title: String
    public let detail: String
    /// The name of the Opener, when macOS reports it.
    public let openerName: String?
    public let rows: [LinkPickerRow<ID>]
    public private(set) var highlightedIndex: Int?
    /// Whether the panel is unfolded from the notch.
    public var isOpen = false

    public init(link: IncomingLink, rows: [LinkPickerRow<ID>]) {
        title = link.title
        detail = link.detail
        openerName = link.opener?.name
        self.rows = rows
    }

    public func handle(_ input: LinkPickerKeyInput) -> LinkPickerOutcome<ID> {
        switch input {
        case .character(let character):
            guard let index = LinkPickerKey.rowIndex(for: character), rows.indices.contains(index) else { return .none }
            highlightedIndex = index
            return .chose(rows[index].id)
        case .down, .right:
            move(by: 1)
            return .none
        case .up, .left:
            move(by: -1)
            return .none
        case .return:
            guard let highlightedIndex else { return .none }
            return .chose(rows[highlightedIndex].id)
        case .escape:
            return .cancelled
        }
    }

    /// Clicking a row chooses it.
    public func choose(_ id: ID) -> LinkPickerOutcome<ID> {
        rows.contains { $0.id == id } ? .chose(id) : .none
    }

    public var highlightedRow: LinkPickerRow<ID>? {
        highlightedIndex.map { rows[$0] }
    }

    /// The first move highlights the first row going down or right, the last one going up or left.
    private func move(by delta: Int) {
        guard !rows.isEmpty else { return }
        guard let current = highlightedIndex else {
            highlightedIndex = delta > 0 ? 0 : rows.count - 1
            return
        }
        highlightedIndex = ((current + delta) % rows.count + rows.count) % rows.count
    }
}

extension LinkPickerModel where ID == ProfileID {
    /// - Parameter alreadyOpenIn: the Profiles that have a Tab showing the link, which get a mark.
    public convenience init(link: IncomingLink, profiles: [Profile], alreadyOpenIn: Set<ProfileID> = []) {
        self.init(link: link, rows: profiles.enumerated().map { index, profile in
            LinkPickerRow(id: profile.id, number: index + 1, symbol: profile.symbol, name: profile.name,
                          isLinkOpen: alreadyOpenIn.contains(profile.id))
        })
    }
}

extension LinkPickerModel where ID == SpaceID {
    public convenience init(link: IncomingLink, spaces: [SpaceChoice]) {
        self.init(link: link, rows: spaces.enumerated().map { index, space in
            LinkPickerRow(id: space.id, number: index + 1, symbol: space.emoji, name: space.name, isLinkOpen: false)
        })
    }
}
