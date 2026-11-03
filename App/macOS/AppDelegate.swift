// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
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

    private var mainWindow: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let context = ProfileWebContext(profileID: Self.defaultProfile.id)
        let session = ProfileSession(profile: Self.defaultProfile) { context.makePage(for: $0) }
        let controller = MainWindowController(session: session, webContext: context)
        controller.showWindow(nil)
        controller.focusCommandBar(nil)
        mainWindow = controller
        NSApp.activate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            mainWindow?.showWindow(nil)
        }
        return true
    }
}
