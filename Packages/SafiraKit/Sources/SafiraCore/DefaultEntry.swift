// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// What the user can do with a default where it is shown.
public enum DefaultControl: Hashable, Sendable {
    /// A switch, with the position it starts in.
    case toggle(isOn: Bool)
    /// A choice the user must make: nothing is preselected.
    case choice
    /// Something Safira offers to do, such as becoming the default browser.
    case action
    /// A fact the user is told. Either it is a reminder, or the behaviour has no switch in this version.
    case information
}

/// One entry of the registry of defaults: a choice Safira makes for the user until they change it. Each default is
/// declared once here, and onboarding and the Defaults window read the same entry (docs/architecture-v1.md §7.2).
public struct DefaultEntry: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// The default value as the user reads it, for example "On" or "Blocked".
    public let value: String
    public let explanation: String
    public let whereToChange: String
    public let control: DefaultControl
    /// Whether the default has a consequence the user should be told about. Onboarding and the Defaults window show
    /// every user-facing entry and no other.
    public let isUserFacing: Bool

    public init(id: String, title: String, value: String, explanation: String, whereToChange: String,
                control: DefaultControl = .information, isUserFacing: Bool = true) {
        self.id = id
        self.title = title
        self.value = value
        self.explanation = explanation
        self.whereToChange = whereToChange
        self.control = control
        self.isUserFacing = isUserFacing
    }
}
