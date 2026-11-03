// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit

@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(submenu(title: "Safira", items: [
            NSMenuItem(title: "About Safira", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: "Hide Safira", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            hideOthers(),
            NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: "Quit Safira", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ]))
        menu.addItem(submenu(title: "File", items: [
            NSMenuItem(title: "New Tab", action: #selector(MainWindowController.newTab(_:)), keyEquivalent: "t"),
            NSMenuItem(title: "Open Command Bar", action: #selector(MainWindowController.focusCommandBar(_:)),
                       keyEquivalent: "l"),
            .separator(),
            NSMenuItem(title: "Close Tab", action: #selector(MainWindowController.closeTab(_:)), keyEquivalent: "w"),
            NSMenuItem(title: "Reopen Closed Tab", action: #selector(MainWindowController.reopenClosedTab(_:)),
                       keyEquivalent: "T"),
            NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "W"),
        ]))
        menu.addItem(submenu(title: "Edit", items: [
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))
        menu.addItem(submenu(title: "View", items: [
            NSMenuItem(title: "Reload Page", action: #selector(MainWindowController.reload(_:)), keyEquivalent: "r"),
            NSMenuItem(title: "Focus Tab List", action: #selector(MainWindowController.focusTabList(_:)),
                       keyEquivalent: ""),
        ]))
        menu.addItem(submenu(title: "History", items: [
            NSMenuItem(title: "Back", action: #selector(MainWindowController.goBack(_:)), keyEquivalent: "["),
            NSMenuItem(title: "Forward", action: #selector(MainWindowController.goForward(_:)), keyEquivalent: "]"),
        ]))
        let window = submenu(title: "Window", items: [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""),
            .separator(),
            NSMenuItem(title: "Show Previous Tab", action: #selector(MainWindowController.showPreviousTab(_:)),
                       keyEquivalent: "{"),
            NSMenuItem(title: "Show Next Tab", action: #selector(MainWindowController.showNextTab(_:)),
                       keyEquivalent: "}"),
            arrowItem(title: "Move Tab Up", action: #selector(MainWindowController.moveTabUp(_:)),
                      arrow: NSUpArrowFunctionKey),
            arrowItem(title: "Move Tab Down", action: #selector(MainWindowController.moveTabDown(_:)),
                      arrow: NSDownArrowFunctionKey),
        ])
        menu.addItem(window)
        NSApplication.shared.windowsMenu = window.submenu
        return menu
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }

    /// ⌥⌘ with an arrow key.
    private static func arrowItem(title: String, action: Selector, arrow: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: String(Character(UnicodeScalar(arrow)!)))
        item.keyEquivalentModifierMask = [.command, .option]
        return item
    }

    private static func hideOthers() -> NSMenuItem {
        let item = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        item.keyEquivalentModifierMask = [.command, .option]
        return item
    }
}
