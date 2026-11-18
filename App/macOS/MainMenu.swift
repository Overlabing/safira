// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import CommandKit
import CommandKitAppKit
import Commands
import LinkRouting
import SafiraCore
import SafiraSettings

@MainActor
enum MainMenu {
    static func make(updates: UpdateController, diagnostics: DiagnosticsController, links: LinkController,
                     shortcuts: ShortcutBindings<CommandID>, app: AppDelegate) -> NSMenu {
        var commandItems: [CommandID: NSMenuItem] = [:]
        func item(_ id: CommandID, _ action: Selector?) -> NSMenuItem {
            let made = commandItem(id, action, shortcuts)
            commandItems[id] = made
            return made
        }
        /// An item that opens Settings in the key window (the Main window or a Private window, whichever answers it
        /// first), or in the Main window when no window is key; a command's item when the opener has a command.
        func settingsItem(_ opener: SettingsOpener, title: String) -> NSMenuItem {
            let action = #selector(AppDelegate.openSettings(_:))
            let made = opener.command.map { item($0, action) } ?? NSMenuItem(title: title, action: action, keyEquivalent: "")
            made.representedObject = opener.rawValue
            return made
        }
        let menu = NSMenu()
        menu.addItem(submenu(title: "Safira", items: [
            NSMenuItem(title: String(localized: "About Safira", comment: "Menu item"),
                       action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""),
            .separator(),
            settingsItem(.settings, title: ""),
            .separator(),
            target(updates, NSMenuItem(title: String(localized: "Check for Updates…", comment: "Menu item"),
                                       action: #selector(UpdateController.checkForUpdates(_:)), keyEquivalent: "")),
            target(updates, NSMenuItem(title: UpdateSettings.automaticChecksTitle, action: #selector(UpdateController.toggleAutomaticChecks(_:)), keyEquivalent: "")),
            .separator(),
            settingsItem(.shortcuts, title: String(localized: "Shortcuts…", comment: "Menu item")),
            settingsItem(.defaults, title: String(localized: "Defaults…", comment: "Menu item")),
            .separator(),
            target(links, NSMenuItem(title: String(localized: "Make Safira the Default Browser…", comment: "Menu item"),
                                     action: #selector(LinkController.makeDefaultBrowser(_:)),
                                     keyEquivalent: "")),
            target(links, NSMenuItem(title: LinkChoiceLogSettings.title, action: #selector(LinkController.toggleChoiceLog(_:)),
                                     keyEquivalent: "")),
            target(links, NSMenuItem(title: MatchingTabSettings.title, action: #selector(LinkController.toggleMatchingTabs(_:)),
                                     keyEquivalent: "")),
            target(links, NSMenuItem(title: AskForSpaceSettings.title, action: #selector(LinkController.toggleAskForSpace(_:)),
                                     keyEquivalent: "")),
            settingsItem(.linkRules, title: String(localized: "Link Rules…", comment: "Menu item")),
            target(links, NSMenuItem(title: String(localized: "Show Link Rules in Finder", comment: "Menu item"),
                                     action: #selector(LinkController.showLinkRules(_:)),
                                     keyEquivalent: "")),
            target(links, NSMenuItem(title: String(localized: "Grant Access to Slack's Folder…", comment: "Menu item"),
                                     action: #selector(LinkController.grantSlackFolder(_:)),
                                     keyEquivalent: "")),
            target(links, NSMenuItem(title: String(localized: "Forget Slack's Folder", comment: "Menu item"),
                                     action: #selector(LinkController.forgetSlackFolder(_:)),
                                     keyEquivalent: "")),
            .separator(),
            NSMenuItem(title: String(localized: "Hide Safira", comment: "Menu item"),
                       action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            hideOthers(),
            NSMenuItem(title: String(localized: "Show All", comment: "Menu item"),
                       action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""),
            .separator(),
            item(.quit, #selector(NSApplication.terminate(_:))),
        ]))
        menu.addItem(submenu(title: String(localized: "File", comment: "Menu bar title"), items: [
            item(.newTab, #selector(MainWindowController.newTab(_:))),
            target(app, item(.newPrivateWindow, #selector(AppDelegate.newPrivateWindow(_:)))),
            item(.openCommandBar, #selector(MainWindowController.focusCommandBar(_:))),
            .separator(),
            item(.closeTab, #selector(MainWindowController.closeTab(_:))),
            item(.reopenClosedTab, #selector(MainWindowController.reopenClosedTab(_:))),
            .separator(),
            item(.togglePin, #selector(MainWindowController.togglePin(_:))),
            item(.backToPinnedAddress, #selector(MainWindowController.backToPinnedAddress(_:))),
            item(.newFolder, #selector(MainWindowController.newFolder(_:))),
            .separator(),
            item(.closeWindow, #selector(NSWindow.performClose(_:))),
            .separator(),
            item(.printPage, #selector(MainWindowController.printPage(_:))),
        ]))
        menu.addItem(submenu(title: String(localized: "Edit", comment: "Menu bar title"), items: [
            NSMenuItem(title: String(localized: "Cut", comment: "Menu item"),
                       action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: String(localized: "Copy", comment: "Menu item"),
                       action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: String(localized: "Paste", comment: "Menu item"),
                       action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: String(localized: "Select All", comment: "Menu item"),
                       action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
            .separator(),
            item(.findInPage, #selector(MainWindowController.findInPage(_:))),
            item(.findNext, #selector(MainWindowController.findNext(_:))),
            item(.findPrevious, #selector(MainWindowController.findPrevious(_:))),
        ]))
        menu.addItem(submenu(title: String(localized: "View", comment: "Menu bar title"), items: [
            item(.reload, #selector(MainWindowController.reload(_:))),
            .separator(),
            item(.zoomIn, #selector(MainWindowController.zoomIn(_:))),
            item(.zoomOut, #selector(MainWindowController.zoomOut(_:))),
            item(.actualSize, #selector(MainWindowController.actualSize(_:))),
            .separator(),
            webContentItem(title: WebContentSettings.fraudulentSiteWarningTitle,
                           explanation: WebContentSettings.fraudulentSiteWarningExplanation,
                           action: #selector(MainWindowController.toggleFraudulentSiteWarning(_:))),
            webContentItem(title: WebContentSettings.autoplayingSoundTitle,
                           explanation: WebContentSettings.autoplayingSoundExplanation,
                           action: #selector(MainWindowController.toggleAutoplayingSound(_:))),
            webContentItem(title: String(localized: "Reject Cookie Prompts", comment: "View menu: the cookie prompts switch"),
                           explanation: WebContentSettings.cookiePromptsExplanation,
                           action: #selector(MainWindowController.toggleCookiePrompts(_:))),
            .separator(),
            item(.compactMode, #selector(MainWindowController.toggleCompactMode(_:))),
            item(.showSidebar, #selector(MainWindowController.toggleRevealedSidebar(_:))),
            item(.focusTabList, #selector(MainWindowController.focusTabList(_:))),
        ]))
        menu.addItem(submenu(title: String(localized: "History", comment: "Menu bar title"), items: [
            item(.goBack, #selector(MainWindowController.goBack(_:))),
            item(.goForward, #selector(MainWindowController.goForward(_:))),
        ]))
        menu.addItem(submenu(title: String(localized: "Spaces", comment: "Menu bar title"), items: [
            item(.newSpace, #selector(MainWindowController.newSpace(_:))),
            item(.renameSpace, #selector(MainWindowController.renameSpace(_:))),
            item(.deleteSpace, #selector(MainWindowController.deleteSpace(_:))),
            .separator(),
            item(.previousSpace, #selector(MainWindowController.showPreviousSpace(_:))),
            item(.nextSpace, #selector(MainWindowController.showNextSpace(_:))),
            item(.moveSpaceLeft, #selector(MainWindowController.moveSpaceLeft(_:))),
            item(.moveSpaceRight, #selector(MainWindowController.moveSpaceRight(_:))),
            .separator(),
        ] + CommandID.selectSpaceCommands.map { id in
            numbered(item(id, #selector(MainWindowController.showSpaceNumber(_:))), id.spaceNumber)
        }))
        menu.addItem(submenu(title: String(localized: "Profiles", comment: "Menu bar title"), items: [
            item(.newProfile, #selector(MainWindowController.newProfile(_:))),
            item(.renameProfile, #selector(MainWindowController.renameProfile(_:))),
            item(.deleteProfile, #selector(MainWindowController.deleteProfile(_:))),
            .separator(),
            settingsItem(.sitePermissions, title: ""),
            item(.clearBrowsingData, #selector(MainWindowController.clearBrowsingData(_:))),
            .separator(),
            item(.previousProfile, #selector(MainWindowController.showPreviousProfile(_:))),
            item(.nextProfile, #selector(MainWindowController.showNextProfile(_:))),
        ]))
        let window = submenu(title: String(localized: "Window", comment: "Menu bar title"), items: [
            NSMenuItem(title: String(localized: "Minimize", comment: "Menu item"),
                       action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: String(localized: "Zoom", comment: "Menu item"),
                       action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""),
            .separator(),
            item(.showDownloads, #selector(MainWindowController.showDownloads(_:))),
            .separator(),
            item(.previousTab, #selector(MainWindowController.showPreviousTab(_:))),
            item(.nextTab, #selector(MainWindowController.showNextTab(_:))),
            item(.moveTabUp, #selector(MainWindowController.moveTabUp(_:))),
            item(.moveTabDown, #selector(MainWindowController.moveTabDown(_:))),
            .separator(),
        ] + CommandID.selectTabCommands.map { id in
            numbered(item(id, #selector(MainWindowController.showTabNumber(_:))), id.tabNumber)
        })
        menu.addItem(window)
        NSApplication.shared.windowsMenu = window.submenu
        let help = submenu(title: String(localized: "Help", comment: "Menu bar title"), items: [
            target(diagnostics, NSMenuItem(title: String(localized: "Debug Mode", comment: "Menu item"),
                                           action: #selector(DiagnosticsController.toggleDebugMode(_:)),
                                           keyEquivalent: "")),
            target(diagnostics, NSMenuItem(title: String(localized: "Export Diagnostic Logs…", comment: "Menu item"),
                                           action: #selector(DiagnosticsController.exportDiagnosticLogs(_:)),
                                           keyEquivalent: "")),
        ])
        menu.addItem(help)
        NSApplication.shared.helpMenu = help.submenu
        for alias in SafiraShortcuts.menuAliases(shortcuts) {
            if let original = commandItems[alias.command] { addAlias(alias.shortcut, of: original) }
        }
        return menu
    }

    /// A second key for a command's item, as Safari takes ⌘= for ⌘+: a hidden copy of the item that only answers its
    /// key, next to the item so that it validates the same way.
    private static func addAlias(_ shortcut: Shortcut, of original: NSMenuItem) {
        guard let menu = original.menu else { return }
        let alias = NSMenuItem(title: original.title, action: original.action, keyEquivalent: String(shortcut.key))
        alias.keyEquivalentModifierMask = shortcut.modifierFlags
        alias.target = original.target
        alias.tag = original.tag
        alias.isHidden = true
        alias.allowsKeyEquivalentWhenHidden = true
        menu.insertItem(alias, at: menu.index(of: original) + 1)
    }

    private static func submenu(title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        items.forEach(submenu.addItem)
        item.submenu = submenu
        return item
    }

    /// A menu item for a command: its title, and the key equivalent of the bindings in force (CommandKit's menu key,
    /// never a key that edits text).
    private static func commandItem(_ id: CommandID, _ action: Selector?, _ bindings: ShortcutBindings<CommandID>) -> NSMenuItem {
        let item = NSMenuItem(title: id.title, action: action, keyEquivalent: "")
        if let shortcut = bindings.shortcut(id) {
            item.keyEquivalent = String(shortcut.key)
            item.keyEquivalentModifierMask = shortcut.modifierFlags
        }
        return item
    }

    /// The window reads the number of the Tab or Space a numbered item shows from its tag.
    private static func numbered(_ item: NSMenuItem, _ number: Int?) -> NSMenuItem {
        item.tag = number ?? 0
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
        let item = NSMenuItem(title: String(localized: "Hide Others", comment: "Menu item"),
                              action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        item.keyEquivalentModifierMask = [.command, .option]
        return item
    }
}
