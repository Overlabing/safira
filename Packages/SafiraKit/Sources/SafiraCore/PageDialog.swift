// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// A page's `alert()`, `confirm()` or `prompt()`, as the window shows it.
public struct PageDialog: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case alert
        case confirm
        /// `prompt()`, with the text the field starts with.
        case prompt(defaultText: String)
    }

    public var kind: Kind
    public var message: String
    /// The host of the frame that asked; nil for a page without one (a local file, a `data:` page).
    public var site: String?
    /// The page has already shown a dialog since it loaded: the sheet offers to stop its dialogs.
    public var offersToStopDialogs: Bool

    public init(kind: Kind, message: String, site: String?, offersToStopDialogs: Bool = false) {
        self.kind = kind
        self.message = message
        self.site = site
        self.offersToStopDialogs = offersToStopDialogs
    }
}

/// What the user answered to a `PageDialog`.
public struct PageDialogResponse: Hashable, Sendable {
    /// OK rather than Cancel; an alert has only OK.
    public var isAccepted: Bool
    /// The text of a `prompt()` field.
    public var text: String
    /// The user asked for no more dialogs from this page.
    public var stopsDialogs: Bool

    public init(isAccepted: Bool, text: String = "", stopsDialogs: Bool = false) {
        self.isAccepted = isAccepted
        self.text = text
        self.stopsDialogs = stopsDialogs
    }

    /// The answer a page gets when nobody can be asked, or when the user stopped its dialogs.
    public static let declined = PageDialogResponse(isAccepted: false)
}

/// Counts a page's dialogs between two documents. From the second one on, the sheet offers to stop them, so a page
/// that loops `alert()` cannot lock the window; once stopped, the page's dialogs are declined without a sheet until it
/// loads another document.
public struct PageDialogGate: Hashable, Sendable {
    private var shownCount = 0
    public private(set) var isStopped = false

    public init() {}

    /// The dialog to show, or nil when the page's dialogs are stopped.
    public mutating func dialog(_ kind: PageDialog.Kind, message: String, site: String?) -> PageDialog? {
        guard !isStopped else { return nil }
        shownCount += 1
        return PageDialog(kind: kind, message: message, site: site, offersToStopDialogs: shownCount > 1)
    }

    /// Only a dialog that offered to stop the page's dialogs can stop them.
    public mutating func answered(_ response: PageDialogResponse) {
        if response.stopsDialogs, shownCount > 1 { isStopped = true }
    }

    /// The page committed a new document.
    public mutating func newDocument() {
        self = PageDialogGate()
    }
}

/// What a page's `<input type="file">` asks for.
public struct FileChoice: Hashable, Sendable {
    public var allowsMultipleSelection: Bool
    public var allowsDirectories: Bool

    public init(allowsMultipleSelection: Bool, allowsDirectories: Bool) {
        self.allowsMultipleSelection = allowsMultipleSelection
        self.allowsDirectories = allowsDirectories
    }
}

/// What a page asks of the window that shows it. One sheet shows at a time.
public struct PagePanels {
    /// Shows a page dialog and returns the user's answer.
    public var dialog: @MainActor (PageDialog) async -> PageDialogResponse
    /// Shows the open panel; nil when the user cancels.
    public var chooseFiles: @MainActor (FileChoice) async -> [URL]?

    public init(dialog: @escaping @MainActor (PageDialog) async -> PageDialogResponse,
                chooseFiles: @escaping @MainActor (FileChoice) async -> [URL]?) {
        self.dialog = dialog
        self.chooseFiles = chooseFiles
    }
}
