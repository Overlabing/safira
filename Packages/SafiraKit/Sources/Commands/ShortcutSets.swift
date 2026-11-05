// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
import Foundation
import Preferences

/// A named set of keyboard shortcuts, chosen at onboarding and editable afterwards. Each is a CommandKit set file,
/// `Presets/<raw value>.json`, that inherits from Safira's own set: a command the browser does not document keeps
/// Safira's key, unless the preset already gives that key to another command.
public enum ShortcutPreset: String, CaseIterable, Sendable, Codable {
    case zen
    case arc
    case safari

    /// The preset's set, read once.
    public var set: ShortcutSet<CommandID> {
        switch self {
        case .zen: BundledSets.zen
        case .arc: BundledSets.arc
        case .safari: BundledSets.safari
        }
    }

    /// The browser's name, a product name that is not translated.
    public var name: String {
        switch self {
        case .zen: "Zen"
        case .arc: "Arc"
        case .safari: "Safari"
        }
    }

    /// The preset of a set; nil for Safira's own set.
    public init?(_ set: ShortcutSet<CommandID>) {
        self.init(rawValue: set.id)
    }

    /// The set's `note` in the user's language. A note is data, not code, so its translation is a manual entry of the
    /// catalog.
    public var localizedNote: String? {
        self.set.note.map { Bundle.module.localizedString(forKey: $0, value: $0, table: "Commands") }
    }
}

/// Safira's side of CommandKit: its own set, its rules and the groups of the Shortcuts window.
public enum SafiraShortcuts {
    /// Safira's own shortcuts (`Presets/safira.json`): in force until a preset is chosen, and the parent of every preset.
    public static var standard: ShortcutSet<CommandID> { BundledSets.safira }

    /// Every set the stored bindings may name.
    public static var sets: [ShortcutSet<CommandID>] { [standard] + ShortcutPreset.allCases.map(\.set) }

    /// The set of a preset, Safira's own without one.
    public static func set(_ preset: ShortcutPreset?) -> ShortcutSet<CommandID> { preset?.set ?? standard }

    /// The menu items that are not commands: the standard editing and window keys, which no command may take.
    public static let fixedMenuItems: [(title: String, shortcut: Shortcut)] = [
        (String(localized: "Cut", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut("x")),
        (String(localized: "Copy", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut("c")),
        (String(localized: "Paste", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut("v")),
        (String(localized: "Select All", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut("a")),
        (String(localized: "Minimize", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut("m")),
        (String(localized: "Hide Safira", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut("h")),
        (String(localized: "Hide Others", table: "Commands", bundle: .module, comment: "Menu item"), Shortcut("h", [.command, .option])),
    ]

    /// - `fixed`: Tab and ⇧Tab leave the Command bar through a responder-chain rule, not a menu item: shown, not changed.
    /// - `reserved`: the fixed menu items' keys.
    /// - `usedWhileTyping`: every command, since the menu hears its key before the page or the Command bar does, so a key
    ///   needs ⌘ or ⌃.
    /// - `beforeFocusedView`: the browser-level shortcuts (⌘T ⌘N ⌘W ⇧⌘T ⌘L ⌘Q ⇧⌘[ ⇧⌘] by default), which a focused web
    ///   page must never swallow, so the window offers them to the menu first.
    public static let rules = BindingRules<CommandID>(
        fixed: [.commandBarNext, .commandBarPrevious],
        reserved: Set(fixedMenuItems.map(\.shortcut)),
        usedWhileTyping: Set(CommandID.allCases),
        beforeFocusedView: [.newTab, .newWindow, .closeTab, .reopenClosedTab, .openCommandBar, .quit, .previousTab, .nextTab])

    /// The sections of the Shortcuts window, in the order of the menus. A command with no behaviour yet is left out.
    public static var groups: [ShortcutReference<CommandID>.Group] {
        [
            .init(id: "tabs", title: String(localized: "Tabs and Windows", table: "Commands", bundle: .module,
                                            comment: "Shortcuts window: section title"),
                  commands: [.newTab, .newPrivateWindow, .openCommandBar, .closeTab, .reopenClosedTab, .closeWindow,
                             .togglePin, .newFolder, .previousTab, .nextTab, .moveTabUp, .moveTabDown]
                      + CommandID.selectTabCommands + [.showDownloads, .quit]),
            .init(id: "view", title: String(localized: "View and History", table: "Commands", bundle: .module,
                                            comment: "Shortcuts window: section title"),
                  commands: [.reload, .compactMode, .showSidebar, .focusTabList, .goBack, .goForward]),
            .init(id: "spaces", title: String(localized: "Spaces", table: "Commands", bundle: .module,
                                              comment: "Shortcuts window: section title"),
                  commands: [.newSpace, .renameSpace, .deleteSpace, .previousSpace, .nextSpace, .moveSpaceLeft,
                             .moveSpaceRight] + CommandID.selectSpaceCommands),
            .init(id: "profiles", title: String(localized: "Profiles", table: "Commands", bundle: .module,
                                                comment: "Shortcuts window: section title"),
                  commands: [.newProfile, .renameProfile, .deleteProfile, .sitePermissions, .clearBrowsingData,
                             .previousProfile, .nextProfile]),
            .init(id: "commandBar", title: String(localized: "Command Bar", table: "Commands", bundle: .module,
                                                  comment: "Shortcuts window: section title"),
                  commands: [.commandBarNext, .commandBarPrevious]),
        ]
    }
}

/// Static storage: a generic `ShortcutSet` cannot hold static stored properties.
private enum BundledSets {
    static let safira = bundled("safira", inheritingFrom: nil)
    static let zen = bundled(ShortcutPreset.zen.rawValue, inheritingFrom: safira)
    static let arc = bundled(ShortcutPreset.arc.rawValue, inheritingFrom: safira)
    static let safari = bundled(ShortcutPreset.safari.rawValue, inheritingFrom: safira)

    /// A missing or unreadable file is a broken build the preset tests catch, never a user's state.
    private static func bundled(_ id: String, inheritingFrom parent: ShortcutSet<CommandID>?) -> ShortcutSet<CommandID> {
        do {
            guard let url = Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Presets") else {
                preconditionFailure("Presets/\(id).json is missing from the bundle")
            }
            return try ShortcutSet(data: Data(contentsOf: url), expecting: id, inheritingFrom: parent)
        } catch {
            preconditionFailure("Presets/\(id).json is unreadable: \(error)")
        }
    }
}

extension ShortcutPreset {
    /// The entry for the Shortcut preset: the user picks Zen, Arc or Safari, and may keep Safira's own shortcuts.
    public static var defaultEntries: [DefaultEntry] {
        [
            DefaultEntry(
                id: "shortcuts.preset",
                title: String(localized: "Shortcut preset", table: "Commands", bundle: .module, comment: "Defaults: entry title"),
                value: String(localized: "Chosen by you", table: "Commands", bundle: .module, comment: "Defaults: value of Shortcut preset"),
                explanation: String(localized: """
                    Zen, Arc or Safari shortcuts. A command the preset has no equivalent for keeps Safira's own \
                    shortcut. Without a preset, Safira's own shortcuts apply. You can change any shortcut afterwards.
                    """, table: "Commands", bundle: .module, comment: "Defaults: explanation of Shortcut preset"),
                whereToChange: String(localized: "Safira menu, Shortcuts…", table: "Commands", bundle: .module,
                                      comment: "Defaults: where to change it; a menu and its item"),
                control: .choice
            ),
        ]
    }
}
