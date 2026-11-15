// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore

/// A page's `alert()`, `confirm()` and `prompt()` and its file input, as sheets on the window, in turn with the
/// permission questions: one sheet at a time.
extension PermissionPrompter {
    var pagePanels: PagePanels {
        PagePanels(
            dialog: { [weak self] dialog in await self?.inTurn { await $0.show(dialog) } ?? .declined },
            chooseFiles: { [weak self] choice in await self?.inTurn { await $0.chooseFiles(choice) } ?? nil })
    }

    /// Like Safari, the sheet names the site that asks, so a page cannot pass its words off as Safira's.
    private func show(_ dialog: PageDialog) async -> PageDialogResponse {
        let alert = NSAlert()
        alert.messageText = dialog.site.map { String(localized: "The page at “\($0)” says:", comment: "Page dialog sheet title; the argument is the site") }
            ?? String(localized: "This page says:", comment: "Page dialog sheet title, for a page without a site")
        alert.informativeText = dialog.message
        alert.addButton(withTitle: String(localized: "OK", comment: "Page dialog sheet"))
        var field: NSTextField?
        switch dialog.kind {
        case .alert:
            break
        case .confirm:
            alert.addButton(withTitle: String(localized: "Cancel", comment: "Page dialog sheet")).keyEquivalent = "\u{1b}"
        case .prompt(let defaultText):
            alert.addButton(withTitle: String(localized: "Cancel", comment: "Page dialog sheet")).keyEquivalent = "\u{1b}"
            let input = NSTextField(string: defaultText)
            input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
            input.setAccessibilityLabel(dialog.message)
            input.widthAnchor.constraint(equalToConstant: 280).isActive = true
            field = input
        }
        var stop: NSButton?
        if dialog.offersToStopDialogs {
            let checkbox = NSButton(
                checkboxWithTitle: String(localized: "Prevent this page from creating additional dialogs", comment: "Page dialog sheet"),
                target: nil, action: nil)
            checkbox.sizeToFit()
            stop = checkbox
        }
        alert.accessoryView = Self.stacked([field, stop].compactMap { $0 })
        if let field { alert.window.initialFirstResponder = field }
        let response = await present(alert)
        return PageDialogResponse(isAccepted: response == .alertFirstButtonReturn,
                                  text: field?.stringValue ?? "",
                                  stopsDialogs: stop?.state == .on)
    }

    private func chooseFiles(_ choice: FileChoice) async -> [URL]? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = choice.allowsDirectories
        panel.allowsMultipleSelection = choice.allowsMultipleSelection
        panel.resolvesAliases = true
        let response: NSApplication.ModalResponse
        if let window = window(), window.isVisible {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = panel.runModal()
        }
        return response == .OK ? panel.urls : nil
    }

    private static func stacked(_ views: [NSView]) -> NSView? {
        guard views.count > 1 else { return views.first }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame.size = stack.fittingSize
        return stack
    }
}
