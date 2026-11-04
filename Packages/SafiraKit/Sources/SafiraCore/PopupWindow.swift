// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// Identifies a popup: a window a page opened with `window.open` and window features, such as a sign-in. It is not a Tab.
public struct PopupID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// The size a page asked for when it opened a window with `window.open(url, name, "width=480,height=640")`.
public struct RequestedWindow: Hashable, Sendable {
    public let width: Double?
    public let height: Double?

    public init(width: Double? = nil, height: Double? = nil) {
        self.width = width
        self.height = height
    }

    /// A scripted `window.open` with dimensions is a sign-in or payment popup that needs its opener alive; one without
    /// features is a link and opens a background Tab (docs/architecture-v1.md §4.3). WebKit's public window features
    /// do not report the `popup` keyword, so dimensions are the signal.
    public var opensFloatingPanel: Bool {
        width != nil || height != nil
    }

    public static let defaultPanelSize = (width: 500.0, height: 640.0)
    public static let panelWidthRange = 320.0...900.0
    public static let panelHeightRange = 360.0...900.0

    /// What the panel measures: the asked size kept within sizes a sign-in form fits in and the screen can show.
    public var panelSize: (width: Double, height: Double) {
        (min(max(width ?? Self.defaultPanelSize.width, Self.panelWidthRange.lowerBound), Self.panelWidthRange.upperBound),
         min(max(height ?? Self.defaultPanelSize.height, Self.panelHeightRange.lowerBound), Self.panelHeightRange.upperBound))
    }
}
