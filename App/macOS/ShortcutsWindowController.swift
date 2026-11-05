// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import CommandKit
import CommandKitAppKit
import Commands
import SwiftUI

/// The window where the user picks a Shortcut preset and changes individual shortcuts. The window is built the first
/// time it is shown: the menu creates this controller at launch, and a window that exists without ever being shown
/// still counts among the app's windows.
@MainActor
final class ShortcutsWindowController: NSWindowController {
    private let shortcuts: ShortcutController

    init(shortcuts: ShortcutController) {
        self.shortcuts = shortcuts
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc func show(_ sender: Any?) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: ShortcutsSettingsView(shortcuts: shortcuts)))
            window.title = String(localized: "Shortcuts", comment: "Window title")
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.setContentSize(NSSize(width: 600, height: 720))
            self.window = window
        }
        window?.center()
        showWindow(nil)
        NSApp.activate()
    }
}

/// As in Oisillon's Shortcuts pane: the preset, then every command by section with its keys on a recorder button. A key
/// refused (taken, reserved, one that would type text) is said in red under its row with the reason; so is a key two
/// commands share, which only changes saved against another version of a preset can cause. Reset gives a command its
/// preset's keys back, Reset All Changes every command.
private struct ShortcutsSettingsView: View {
    let shortcuts: ShortcutController
    @State private var recorder = ShortcutRecorder()
    /// The last key refused, under the row of its command.
    @State private var refusal: Refusal?
    /// A preset picked while the user has changes: they are dropped only once confirmed.
    @State private var pendingPreset: PresetChoice?

    var body: some View {
        let bindings = shortcuts.bindings
        let conflicts = bindings.conflicts
        Form {
            presetSection
            ForEach(ShortcutReference.editableSections(SafiraShortcuts.groups, bindings: bindings, title: \.title)) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        if let command = row.command {
                            ShortcutRow(
                                row: row, command: command, recorder: recorder,
                                problem: problem(for: command, conflicts: conflicts),
                                record: { record($0, for: command) },
                                unbind: {
                                    refusal = nil
                                    shortcuts.unbind(command)
                                },
                                reset: {
                                    refusal = nil
                                    shortcuts.reset(command)
                                })
                        }
                    }
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button {
                        refusal = nil
                        shortcuts.resetAll()
                    } label: {
                        Text("Reset All Changes", comment: "Shortcuts window: button that gives every command its preset's keys back")
                    }
                    .disabled(bindings.overrides.isEmpty)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservedExplanation)
                    Text("Click a shortcut, then press the new keys. Delete removes the shortcut, Escape cancels.",
                         comment: "Shortcuts window footnote")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 480)
        .onDisappear { recorder.stop() }
        .confirmationDialog(
            String(localized: "Change the Shortcut preset?", comment: "Shortcuts window: confirmation title"),
            isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } })
        ) {
            Button(role: .destructive) {
                if let pendingPreset { choose(pendingPreset.preset) }
                pendingPreset = nil
            } label: {
                Text("Change Preset", comment: "Shortcuts window: confirmation button")
            }
        } message: {
            Text("Your shortcut changes will be lost.", comment: "Shortcuts window: confirmation message")
        }
    }

    private var presetSection: some View {
        Section {
            Picker(selection: presetSelection) {
                Text("None chosen (Safira's defaults)").tag(PresetChoice(preset: nil))
                ForEach(ShortcutPreset.allCases, id: \.self) { Text(verbatim: $0.name).tag(PresetChoice(preset: $0)) }
            } label: {
                Text("Preset", comment: "Shortcuts window: the Shortcut preset picker")
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let preset = shortcuts.preset, let source = preset.set.source {
                    HStack(spacing: 4) {
                        Text("Source:").foregroundStyle(.secondary)
                        Link(source.host() ?? source.absoluteString, destination: source)
                        if let checked = preset.set.checked {
                            Text("checked \(checked)").foregroundStyle(.secondary)
                        }
                    }
                    if let note = preset.localizedNote {
                        Text(note)
                    }
                    Text("A command \(preset.name) has no equivalent for keeps Safira's key, marked “Inherited from Safira”. Choosing another preset clears your changes.",
                         comment: "Shortcuts window footnote; the argument is a browser's name")
                } else {
                    Text("Safira's own shortcuts. A preset gives you the keys of Zen, Arc or Safari.",
                         comment: "Shortcuts window footnote without a preset")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var presetSelection: Binding<PresetChoice> {
        Binding(
            get: { PresetChoice(preset: shortcuts.preset) },
            set: { choice in
                guard choice.preset != shortcuts.preset else { return }
                if shortcuts.bindings.overrides.isEmpty { choose(choice.preset) } else { pendingPreset = choice }
            })
    }

    private func choose(_ preset: ShortcutPreset?) {
        refusal = nil
        shortcuts.choose(preset)
    }

    private func record(_ shortcut: Shortcut?, for command: CommandID) {
        guard let shortcut else {
            refusal = Refusal(command: command, error: .notAKey)
            return
        }
        refusal = shortcuts.record(shortcut, for: command).map { Refusal(command: command, error: $0) }
    }

    /// What to say in red under a command: the key just refused, a key it shares with another command, or a key the
    /// menu cannot use.
    private func problem(for command: CommandID, conflicts: [ShortcutConflict<CommandID>]) -> String? {
        if let refusal, refusal.command == command {
            return refusal.error.message(appName: "Safira", title: \.title)
        }
        if let conflict = conflicts.first(where: { $0.commands.contains(command) }),
           let other = conflict.commands.first(where: { $0 != command }) {
            return String(localized: "\(conflict.shortcut.symbols) is also on “\(other.title)”.",
                          comment: "Shortcuts window: two commands share a key; a key, then a command name")
        }
        let bindings = shortcuts.bindings
        if bindings.shortcut(command) == nil, let key = bindings.keys(command).first {
            return String(localized: "\(key.symbols) edits text in a field, so the menu cannot use it.",
                          comment: "Shortcuts window: a key such as ⌃⌘← that is never a menu key")
        }
        return nil
    }

    private var reservedExplanation: String {
        let titles = CommandID.allCases.filter(SafiraShortcuts.rules.beforeFocusedView.contains).map(\.title).formatted()
        return String(localized: "\(titles) reach the menu before the page sees the key, whatever the page does with it.",
                      comment: "Shortcuts window footnote; the argument lists command names")
    }

    private struct Refusal {
        let command: CommandID
        let error: ShortcutBindingError<CommandID>
    }

    /// The picker's tag: a preset, or none for Safira's own shortcuts.
    private struct PresetChoice: Hashable {
        let preset: ShortcutPreset?
    }
}

/// One command: its title (with Changed or Inherited, or the problem in red underneath), Reset once changed, and the
/// recorder showing its keys. A fixed command shows its keys and cannot be changed.
private struct ShortcutRow: View {
    let row: ShortcutReference<CommandID>.Row
    let command: CommandID
    let recorder: ShortcutRecorder
    let problem: String?
    /// The key typed, nil when it forms no shortcut (a dead key).
    let record: (Shortcut?) -> Void
    let unbind: () -> Void
    let reset: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                if row.isOverridden {
                    Button(action: reset) {
                        Text("Reset", comment: "Shortcuts window: gives one command its preset's keys back")
                    }
                    .buttonStyle(.link)
                    .help(String(localized: "Take the preset's key again", comment: "Shortcuts window: help of Reset"))
                }
                if SafiraShortcuts.rules.isRebindable(command) {
                    recorderButton
                } else {
                    Text(keysText).foregroundStyle(.secondary)
                }
            }
        } label: {
            Text(row.title)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if row.isOverridden {
                Text("Changed", comment: "Shortcuts window: the user changed this command's shortcut")
            } else if row.isInherited {
                Text("Inherited from Safira", comment: "Shortcuts window: the preset has no key for this command")
            } else if !SafiraShortcuts.rules.isRebindable(command) {
                Text("Fixed")
            }
        }
    }

    private var isRecording: Bool { recorder.command == command }

    private var keysText: String {
        row.keys.isEmpty ? String(localized: "Unbound", comment: "Shortcuts window: a command with no shortcut")
            : row.keys.joined(separator: "  ")
    }

    /// A bordered button: the keys at rest, Press keys… while recording (accent).
    private var recorderButton: some View {
        Button {
            isRecording ? recorder.stop() : recorder.start(for: command, record: record, unbind: unbind)
        } label: {
            Text(isRecording ? String(localized: "Press keys…", comment: "Shortcuts window: a row waiting for the new keys")
                 : keysText)
                .monospacedDigit()
                .frame(minWidth: 132)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .help(String(localized: "Click, then press the new shortcut; Delete removes it, Escape cancels.",
                     comment: "Shortcuts window: help of a shortcut button"))
        .accessibilityLabel(String(localized: "Shortcut of “\(row.title)”", comment: "Shortcuts window: a recorder button; the argument is a command name"))
        .accessibilityValue(isRecording ? String(localized: "Waiting for a shortcut", comment: "Shortcuts window: a recorder button's value while recording")
                            : keysText)
    }
}

/// While it waits, the next key press of the app is its result: a local monitor sees the key before the menu does, so
/// the key goes nowhere else, and it is read as the window reads keys (`Shortcut(event:)`). Escape cancels; Delete
/// alone removes the command's shortcut; a dead key is reported (nil), not silently dropped. One command at a time.
@MainActor @Observable
private final class ShortcutRecorder {
    private(set) var command: CommandID?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var record: ((Shortcut?) -> Void)?
    @ObservationIgnored private var unbind: (() -> Void)?

    func start(for command: CommandID, record: @escaping (Shortcut?) -> Void, unbind: @escaping () -> Void) {
        stop()
        self.command = command
        self.record = record
        self.unbind = unbind
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // AppKit calls a local monitor on the main thread, inside `sendEvent`: the event stays on the main actor.
            nonisolated(unsafe) let event = event
            MainActor.assumeIsolated { ShortcutRecorder.take(event) }
            return nil
        }
        Self.active = self
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        command = nil
        record = nil
        unbind = nil
        if Self.active === self { Self.active = nil }
    }

    /// The recorder waiting for a key; the monitor's closure reaches it here (a closure capturing `self` would not be
    /// `Sendable`).
    private static weak var active: ShortcutRecorder?

    private static func take(_ event: NSEvent) {
        guard let recorder = active else { return }
        let record = recorder.record
        let unbind = recorder.unbind
        recorder.stop()
        let shortcut = Shortcut(event: event)
        if let shortcut, shortcut.modifiers.isEmpty {
            if shortcut.key == Shortcut.escape { return }
            if shortcut.key == Shortcut.delete { return unbind?() ?? () }
        }
        record?(shortcut)
    }
}
