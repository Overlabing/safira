// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// What in a page keeps its navigation state off the disk. The engine's navigation state can hold form fields and
/// POST bodies.
public struct SensitiveContent: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The page has, or had, a password field in one of its frames.
    public static let passwordField = SensitiveContent(rawValue: 1 << 0)
    /// The page, or one of its frames, was reached by a request with a POST body.
    public static let postBody = SensitiveContent(rawValue: 1 << 1)
}

/// Decision D1 (docs/architecture-v1.md §13.2): a Tab's navigation state is written in full only when no page of its
/// history has a password field or a POST body; otherwise the Tab is saved by its address only.
public enum NavigationStateRule {
    public static func savable(_ navigationState: Data?, sensitiveContent: SensitiveContent) -> Data? {
        sensitiveContent.isEmpty ? navigationState : nil
    }
}

/// The sensitive content seen in each entry of a page's back-forward list. The navigation state holds every entry
/// of the list, so an entry stays sensitive for as long as it is in the list, not only while it is shown.
public struct SensitiveHistory<Entry: Hashable> {
    private var marks: [Entry: SensitiveContent] = [:]

    public init() {}

    public mutating func mark(_ entry: Entry, _ content: SensitiveContent) {
        marks[entry, default: []].formUnion(content)
    }

    /// What the given entries hold together. Marks of entries no longer in the list are dropped.
    public mutating func content(of entries: [Entry]) -> SensitiveContent {
        let present = Set(entries)
        marks = marks.filter { present.contains($0.key) }
        return marks.values.reduce(into: []) { $0.formUnion($1) }
    }
}

/// How a saved Tab comes back when it is first shown.
public enum Restoration: Hashable, Sendable {
    /// Its full navigation state, with the address to load if the engine refuses the state.
    case navigationState(Data, fallback: URL?)
    case address(URL)
    case blank

    /// The navigation state is only trusted on the macOS build that wrote it: its format is the web engine's own.
    public init(_ record: TabRecord, osBuild: String) {
        if let state = record.navigationState, record.navigationStateOSBuild == osBuild {
            self = .navigationState(state, fallback: record.address)
        } else if let address = record.address {
            self = .address(address)
        } else {
            self = .blank
        }
    }
}
