// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Commands
import SwiftUI

/// The window where the user picks a Shortcut preset and changes individual shortcuts.
@MainActor
final class ShortcutsWindowController: NSWindowController {
    init(shortcuts: ShortcutController) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: ShortcutsSettingsView(shortcuts: shortcuts)))
        window.title = "Shortcuts"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 640))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc func show(_ sender: Any?) {
        window?.center()
        showWindow(nil)
        NSApp.activate()
    }
}

/// Records the next key combination the user types. A local monitor sees the key before the menu does, so recording a
/// combination that is already a menu shortcut does not run it.
@MainActor @Observable
private final class ShortcutRecorder {
    private(set) var recording: CommandID?
    private var monitor: Any?

    func start(for command: CommandID, record: @escaping (Shortcut?) -> Void) {
        stop()
        recording = command
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let press = KeyStroke(event)
            let keyCode = event.keyCode
            let consumed = MainActor.assumeIsolated { self?.handle(press, keyCode: keyCode, record: record) ?? false }
            return consumed ? nil : event
        }
    }

    private func handle(_ press: KeyStroke, keyCode: UInt16, record: (Shortcut?) -> Void) -> Bool {
        switch keyCode {
        case 53 where press.modifiers.isEmpty: // Escape cancels
            break
        case 51 where press.modifiers.isEmpty: // Delete removes the shortcut
            record(nil)
        default:
            // A bare letter would be typed into pages: a shortcut needs ⌘, ⌥ or ⌃.
            guard !press.modifiers.isDisjoint(with: [.command, .option, .control]), let shortcut = press.shortcut else {
                return true
            }
            record(shortcut)
        }
        stop()
        return true
    }

    func stop() {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
        recording = nil
    }
}

private struct ShortcutsSettingsView: View {
    let shortcuts: ShortcutController
    @State private var recorder = ShortcutRecorder()

    private static let noPreset = "none"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            presetSection
            if !shortcuts.conflicts.isEmpty {
                conflictSection
            }
            List(CommandRegistry.commands.filter(\.isImplemented)) { command in
                row(command)
            }
            Text(reservedExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Text("Click Change, then press the new keys. Delete removes the shortcut, Escape cancels.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset All Overrides") { shortcuts.resetAll() }
                    .disabled(shortcuts.configuration.overrides.isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 480)
        .onDisappear { recorder.stop() }
    }

    private var presetSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Preset", selection: Binding(
                get: { shortcuts.configuration.preset?.rawValue ?? Self.noPreset },
                set: { shortcuts.choose(ShortcutPreset(rawValue: $0)) }
            )) {
                Text("None chosen (Safira's defaults)").tag(Self.noPreset)
                ForEach(ShortcutPreset.allCases, id: \.rawValue) { Text($0.data.name).tag($0.rawValue) }
            }
            if let preset = shortcuts.configuration.preset {
                let data = preset.data
                HStack(spacing: 4) {
                    Text("Source:").foregroundStyle(.secondary)
                    Link(data.source.host() ?? data.source.absoluteString, destination: data.source)
                    Text("checked \(data.checked)").foregroundStyle(.secondary)
                }
                .font(.footnote)
                if let note = data.note {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var conflictSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(shortcuts.conflicts, id: \.shortcut) { conflict in
                Label("\(conflict.shortcut.display) is used by \(conflictParties(conflict))",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func conflictParties(_ conflict: ShortcutConflict) -> String {
        (conflict.commands.map { CommandRegistry.command($0).title } + conflict.fixedItems).formatted()
    }

    private func row(_ command: Command) -> some View {
        let shortcut = shortcuts.bindings[command.id]
        let override = shortcuts.configuration.overrides[command.id]
        let isRecording = recorder.recording == command.id
        return HStack {
            Text(command.title)
            Spacer()
            Text(isRecording ? "Press keys…" : shortcut?.display ?? "Unbound")
                .monospaced()
                .foregroundStyle(shortcut == nil && !isRecording ? .secondary : .primary)
            if command.isRebindable {
                Button(isRecording ? "Cancel" : "Change") {
                    if isRecording {
                        recorder.stop()
                    } else {
                        recorder.start(for: command.id) { shortcuts.setShortcut($0, for: command.id) }
                    }
                }
                Button("Reset") { shortcuts.resetShortcut(for: command.id) }
                    .disabled(override == nil)
            } else {
                Text("Fixed").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var reservedExplanation: String {
        let titles = CommandRegistry.commands.filter(\.isReserved).map(\.title).formatted()
        return "\(titles) reach the menu before the page sees the key, whatever the page does with it."
    }
}
