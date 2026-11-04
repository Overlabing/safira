// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Commands
import os
import SafiraCore
import SafiraSession
import SafiraStore
import SafiraWeb

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updates = UpdateController()

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.overlabing.safira",
                                    category: "persistence")

    let diagnostics = DiagnosticsController()
    let shortcuts = ShortcutController()
    private(set) lazy var shortcutsWindow = ShortcutsWindowController(shortcuts: shortcuts)
    private var mainWindow: MainWindowController?
    private var registry: ProfileRegistry?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let registry = ProfileRegistry(layout: .application, diagnostics: diagnostics.logger) { message, error in
            Self.log.error("\(message, privacy: .public): \(error, privacy: .private)")
        }
        self.registry = registry
        diagnostics.attach(to: registry)
        let controller = MainWindowController(registry: registry, shortcuts: shortcuts)
        controller.showWindow(nil)
        controller.focusCommandBar(nil)
        mainWindow = controller
        NSApp.activate()
        keepMenuInStepWithShortcuts()
    }

    func rebuildMenu() {
        NSApp.mainMenu = MainMenu.make(updates: updates, diagnostics: diagnostics, shortcuts: shortcuts.bindings,
                                       shortcutsWindow: shortcutsWindow)
    }

    /// The menu carries the key equivalents, so a change of preset or override rebuilds it.
    private func keepMenuInStepWithShortcuts() {
        withObservationTracking {
            _ = shortcuts.bindings
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.rebuildMenu()
                self?.keepMenuInStepWithShortcuts()
            }
        }
    }

    /// Quitting waits for the last save of every Profile's Tabs and settings.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let registry else { return .terminateNow }
        Task {
            await registry.saveAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            mainWindow?.showWindow(nil)
        }
        return true
    }
}
