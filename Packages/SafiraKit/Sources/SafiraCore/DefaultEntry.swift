// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// One entry of the registry of defaults: a choice Safira makes for the user until they change it. Each default is
/// declared once here, and onboarding and the settings read the same entry (docs/architecture-v1.md §7.2).
public struct DefaultEntry: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// The default value as the user reads it, for example "On" or "Blocked".
    public let value: String
    public let explanation: String
    public let whereToChange: String

    public init(id: String, title: String, value: String, explanation: String, whereToChange: String) {
        self.id = id
        self.title = title
        self.value = value
        self.explanation = explanation
        self.whereToChange = whereToChange
    }
}
