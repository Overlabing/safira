// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Commands
import SafiraCore

@MainActor
enum MainMenu {
    static func make(updates: UpdateController, diagnostics: DiagnosticsController, shortcuts: KeyBindings,
                     shortcutsWindow: ShortcutsWindowController) -> NSMenu {
        func item(_ id: CommandID, _ action: Selector?) -> NSMenuItem { commandItem(id, action, shortcuts) }
        let menu = NSMenu()
        menu.addItem(submenu(title: "Safira", items: [
            NSMenuItem(title: "About Safira", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""),
            .separator(),
            target(updates, NSMenuItem(title: "Check for Updates…", action: #selector(UpdateController.checkForUpdates(_:)), keyEquivalent: "")),
            target(updates, NSMenuItem(title: "Check for Updates Automatically", action: #selector(UpdateController.toggleAutomaticChecks(_:)), keyEquivalent: "")),
            .separator(),
            target(shortcutsWindow, NSMenuItem(title: "Shortcuts…", action: #selector(ShortcutsWindowController.show(_:)),
                                               keyEquivalent: "")),
            .separator(),
            NSMenuItem(title: "Hide Safira", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            hideOthers(),
            NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""),
            .separator(),
            item(.quit, #selector(NSApplication.terminate(_:))),
        ]))
        menu.addItem(submenu(title: "File", items: [
            item(.newTab, #selector(MainWindowController.newTab(_:))),
            item(.openCommandBar, #selector(MainWindowController.focusCommandBar(_:))),
            .separator(),
            item(.closeTab, #selector(MainWindowController.closeTab(_:))),
            item(.reopenClosedTab, #selector(MainWindowController.reopenClosedTab(_:))),
            item(.closeWindow, #selector(NSWindow.performClose(_:))),
        ]))
        menu.addItem(submenu(title: "Edit", items: [
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]))
        menu.addItem(submenu(title: "View", items: [
            item(.reload, #selector(MainWindowController.reload(_:))),
            .separator(),
            webContentItem(title: WebContentSettings.fraudulentSiteWarningTitle,
                           explanation: WebContentSettings.fraudulentSiteWarningExplanation,
                           action: #selector(MainWindowController.toggleFraudulentSiteWarning(_:))),
            webContentItem(title: WebContentSettings.autoplayingSoundTitle,
                           explanation: WebContentSettings.autoplayingSoundExplanation,
                           action: #selector(MainWindowController.toggleAutoplayingSound(_:))),
            .separator(),
            item(.focusTabList, #selector(MainWindowController.focusTabList(_:))),
        ]))
        menu.addItem(submenu(title: "History", items: [
            item(.goBack, #selector(MainWindowController.goBack(_:))),
            item(.goForward, #selector(MainWindowController.goForward(_:))),
        ]))
        let window = submenu(title: "Window", items: [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""),
            .separator(),
            item(.previousTab, #selector(MainWindowController.showPreviousTab(_:))),
            item(.nextTab, #selector(MainWindowController.showNextTab(_:))),
            item(.moveTabUp, #selector(MainWindowController.moveTabUp(_:))),
            item(.moveTabDown, #selector(MainWindowController.moveTabDown(_:))),
        ])
        menu.addItem(window)
        NSApplication.shared.windowsMenu = window.submenu
        let help = submenu(title: "Help", items: [
            target(diagnostics, NSMenuItem(title: "Debug Mode", action: #selector(DiagnosticsController.toggleDebugMode(_:)),
                                           keyEquivalent: "")),
            target(diagnostics, NSMenuItem(title: "Export Diagnostic Logs…",
                                           action: #selector(DiagnosticsController.exportDiagnosticLogs(_:)),
                                           keyEquivalent: "")),
        ])
        menu.addItem(help)
        NSApplication.shared.helpMenu = help.submenu
        return menu
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }

    /// A menu item for a registry command: its title and key equivalent come from the registry and the bindings in force.
    private static func commandItem(_ id: CommandID, _ action: Selector?, _ bindings: KeyBindings) -> NSMenuItem {
        let item = NSMenuItem(title: CommandRegistry.command(id).title, action: action, keyEquivalent: "")
        if let shortcut = bindings[id] {
            item.keyEquivalent = shortcut.menuKeyEquivalent
            item.keyEquivalentModifierMask = shortcut.modifiers.eventFlags
        }
        return item
    }

    private static func target(_ target: AnyObject, _ item: NSMenuItem) -> NSMenuItem {
        item.target = target
        return item
    }

    private static func webContentItem(title: String, explanation: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.toolTip = explanation
        return item
    }

    private static func hideOthers() -> NSMenuItem {
        let item = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        item.keyEquivalentModifierMask = [.command, .option]
        return item
    }
}
