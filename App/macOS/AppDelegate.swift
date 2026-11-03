// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Commands
import SafiraCore
import SafiraSession
import SafiraWeb

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updates = UpdateController()

    /// The single default Profile until Profiles can be created; a fixed identifier keeps its data store across
    /// launches before anything else is persisted.
    private static let defaultProfile = Profile(
        id: ProfileID(rawValue: UUID(uuidString: "D4AAF7AE-EE5A-45FD-A219-AFC5EA8C1654")!),
        name: "Default"
    )

    let diagnostics = DiagnosticsController()
    let shortcuts = ShortcutController()
    private(set) lazy var shortcutsWindow = ShortcutsWindowController(shortcuts: shortcuts)
    private var mainWindow: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let context = ProfileWebContext(profileID: Self.defaultProfile.id)
        context.diagnostics = diagnostics.logger
        let session = ProfileSession(profile: Self.defaultProfile) { context.makePage(for: $0) }
        diagnostics.attach(to: session)
        let controller = MainWindowController(session: session, webContext: context, shortcuts: shortcuts)
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            mainWindow?.showWindow(nil)
        }
        return true
    }
}
