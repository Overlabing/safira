// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import LinkRouting
import Observation
import SafiraCore

/// One Profile offered by the Link picker.
public struct LinkPickerRow: Hashable, Identifiable, Sendable {
    public let id: ProfileID
    /// The position shown to the user, starting at 1. Only 1 to 9 have a number key.
    public let number: Int
    public let symbol: String
    public let name: String

    public var numberKey: Character? {
        number <= 9 ? Character(String(number)) : nil
    }
}

/// What a key did to the Link picker.
public enum LinkPickerOutcome: Hashable, Sendable {
    case none
    case chose(ProfileID)
    /// The user dismissed the question; the link is dropped.
    case cancelled
}

/// The state of the Link picker. Nothing is highlighted when it opens: a number key chooses a row at once, an arrow
/// key highlights one and Return then chooses the highlighted row. Return does nothing while no row is highlighted.
@MainActor
@Observable
public final class LinkPickerModel {
    public let title: String
    public let detail: String
    /// The name of the Opener, when macOS reports it.
    public let openerName: String?
    public let rows: [LinkPickerRow]
    public private(set) var highlightedIndex: Int?
    /// Whether the panel is unfolded from the notch.
    public var isOpen = false

    public init(link: IncomingLink, profiles: [Profile]) {
        title = link.title
        detail = link.detail
        openerName = link.opener?.name
        rows = profiles.enumerated().map { index, profile in
            LinkPickerRow(id: profile.id, number: index + 1, symbol: profile.symbol, name: profile.name)
        }
    }

    public func handle(_ input: LinkPickerKeyInput) -> LinkPickerOutcome {
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
    public func choose(_ id: ProfileID) -> LinkPickerOutcome {
        rows.contains { $0.id == id } ? .chose(id) : .none
    }

    public var highlightedRow: LinkPickerRow? {
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
