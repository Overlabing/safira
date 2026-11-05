// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Observation
import Preferences
import SafiraCore

/// The list of defaults as the user sees it: every user-facing entry of the registry, with the position of its switch.
/// Onboarding holds the positions until the user finishes; the Defaults window applies each change as it happens.
@MainActor
@Observable
public final class DefaultsSummaryModel {
    public let entries: [DefaultEntry]
    public private(set) var toggles: [String: Bool]
    /// What a choice or an offer currently says, by entry identifier, for example the engine's name.
    public var displayedValues: [String: String] = [:]
    @ObservationIgnored private let apply: ((String, Bool) -> Void)?

    /// - Parameters:
    ///   - current: the position of a switch right now; nil for one it knows nothing about, which then starts at the
    ///     entry's default.
    ///   - apply: called with every change, in the Defaults window; nil during onboarding.
    public init(entries: [DefaultEntry] = DefaultsRegistry.entries.userFacing, current: (String) -> Bool? = { _ in nil },
                apply: ((String, Bool) -> Void)? = nil) {
        self.entries = entries
        self.apply = apply
        var toggles: [String: Bool] = [:]
        for entry in entries {
            guard case .toggle(let isOn) = entry.control else { continue }
            toggles[entry.id] = current(entry.id) ?? isOn
        }
        self.toggles = toggles
    }

    public func isOn(_ id: String) -> Bool {
        toggles[id] ?? false
    }

    public func setOn(_ isOn: Bool, for id: String) {
        guard toggles[id] != nil, toggles[id] != isOn else { return }
        toggles[id] = isOn
        apply?(id, isOn)
    }

    /// The value to show next to an entry: the live one when there is one, else the documented default.
    public func displayedValue(of entry: DefaultEntry) -> String {
        displayedValues[entry.id] ?? entry.value
    }
}
