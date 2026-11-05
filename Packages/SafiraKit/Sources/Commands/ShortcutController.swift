// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CommandKit
import Observation
import Preferences

/// The live shortcuts: CommandKit's bindings the user edits, saved on every change. Menus, the window's reserved keys,
/// the sidebar and the Shortcuts window read `bindings`. Choosing another preset drops the user's changes, since they
/// were made against the previous one.
@MainActor @Observable
public final class ShortcutController {
    public private(set) var bindings: ShortcutBindings<CommandID>
    private let store: ShortcutStore

    /// - Parameter unreadable: told when the saved shortcuts could not be read and Safira's own replaced them.
    public init(store: ShortcutStore = ShortcutStore(), unreadable: (PreferenceError) -> Void) {
        self.store = store
        bindings = store.load(unreadable: unreadable)
    }

    /// The chosen preset; nil while Safira's own shortcuts apply.
    public var preset: ShortcutPreset? { ShortcutPreset(bindings.set) }

    /// Keys bound to several commands: only stored changes made against another version of a set can cause one.
    public var conflicts: [ShortcutConflict<CommandID>] { bindings.conflicts }

    public func choose(_ preset: ShortcutPreset?) {
        update { $0.choose(SafiraShortcuts.set(preset)) }
    }

    /// Makes `shortcut` the command's key; returns why it was refused, changing nothing, when Safira's rules or another
    /// command already have it.
    @discardableResult
    public func record(_ shortcut: Shortcut, for command: CommandID) -> ShortcutBindingError<CommandID>? {
        var changed = bindings
        do {
            try changed.record(shortcut, for: command, rules: SafiraShortcuts.rules)
        } catch {
            return error
        }
        update { $0 = changed }
        return nil
    }

    /// The user removes the command's shortcut: no key, even one the set gives it, until `reset`. Returns why it was
    /// refused, changing nothing, for a command whose keys are fixed.
    @discardableResult
    public func unbind(_ command: CommandID) -> ShortcutBindingError<CommandID>? {
        var changed = bindings
        do {
            try changed.unbind(command, rules: SafiraShortcuts.rules)
        } catch {
            return error
        }
        update { $0 = changed }
        return nil
    }

    /// Back to what the set says for this command.
    public func reset(_ command: CommandID) {
        update { $0.reset(command) }
    }

    public func resetAll() {
        update { $0.resetAll() }
    }

    /// Whether a key press goes to the menu before the focused view, even a web page that handles the key itself.
    public func takesKeyBeforeFocusedView(_ shortcut: Shortcut) -> Bool {
        bindings.takesKeyBeforeFocusedView(shortcut, rules: SafiraShortcuts.rules)
    }

    private func update(_ change: (inout ShortcutBindings<CommandID>) -> Void) {
        var changed = bindings
        change(&changed)
        guard changed != bindings else { return }
        bindings = changed
        store.save(changed)
    }
}
