// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Observation
import WebKit

/// An extension's action as the active Tab shows it: WebKit keeps one action per Tab, which the extension may
/// change for that Tab alone (its badge, its title, whether it is enabled).
public struct ExtensionActionItem: Identifiable {
    /// The extension's identifier (`browser.runtime.id`).
    public let id: String
    /// The extension's name, which VoiceOver reads first.
    public let name: String
    /// The action's title (`action.setTitle`), the manifest's `default_title` until the extension changes it.
    public let label: String
    /// The action's badge (`action.setBadgeText`); empty when there is none.
    public let badgeText: String
    public let isEnabled: Bool
    public let icon: NSImage?

    public init(id: String, name: String, label: String, badgeText: String, isEnabled: Bool, icon: NSImage?) {
        self.id = id
        self.name = name
        self.label = label
        self.badgeText = badgeText
        self.isEnabled = isEnabled
        self.icon = icon
    }
}

/// How the sidebar shows the actions: one button each, or a single overflow button once there are more than fit
/// beside Back, Forward and Reload.
public enum ExtensionActionLayout: Equatable {
    case buttons([String])
    case overflow([String])

    /// Two buttons fit in the head row; a third would squeeze the address field below its placeholder.
    public static let inlineLimit = 2

    public init(identifiers: [String]) {
        self = identifiers.count > Self.inlineLimit ? .overflow(identifiers) : .buttons(identifiers)
    }
}

/// The actions of one Profile's extensions, for the active Tab, in the order the sidebar shows them.
@MainActor
@Observable
public final class ExtensionActions {
    public private(set) var items: [ExtensionActionItem] = []

    /// The side, in points, of the icons WebKit is asked for.
    static let iconSide: CGFloat = 16

    public var layout: ExtensionActionLayout {
        ExtensionActionLayout(identifiers: items.map(\.id))
    }

    func update(_ items: [ExtensionActionItem]) {
        self.items = items
    }
}

/// Where the app shows an action's popup: the button it belongs to, or the overflow button when it is in there.
/// WebKit calls it for a click and for `action.openPopup()` from the service worker alike; the closure throws when
/// there is no button to anchor the popup to.
public typealias ExtensionPopupPresenter = @MainActor (_ extensionID: String, _ action: WKWebExtension.Action) throws -> Void

/// Refused when an extension asks for its popup and the window cannot show it.
public struct ExtensionPopupUnavailable: Error {
    public init() {}
}
