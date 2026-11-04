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

    /// The single default Profile until Profiles can be created; a fixed identifier keeps its data store across
    /// launches.
    private static let defaultProfile = Profile(
        id: ProfileID(rawValue: UUID(uuidString: "D4AAF7AE-EE5A-45FD-A219-AFC5EA8C1654")!),
        name: "Default"
    )
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.overlabing.safira",
                                    category: "persistence")

    let diagnostics = DiagnosticsController()
    let shortcuts = ShortcutController()
    private(set) lazy var shortcutsWindow = ShortcutsWindowController(shortcuts: shortcuts)
    private var mainWindow: MainWindowController?
    private var autosave: SessionAutosave?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let layout = StoreLayout.application
        let (profile, database) = Self.openProfile(in: layout)
        let context = ProfileWebContext(profileID: profile.id)
        context.diagnostics = diagnostics.logger
        let session = ProfileSession(profile: profile) { context.makePage(for: $0) }
        do {
            session.restore(try database.savedSession())
        } catch {
            Self.log.error("The saved Tabs could not be read: \(error, privacy: .private)")
        }
        let autosave = SessionAutosave(session: session, database: database)
        autosave.onError = { Self.log.error("The Tabs could not be saved: \($0, privacy: .private)") }
        autosave.start()
        self.autosave = autosave
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

    /// Quitting waits for the last save of the Tabs.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let autosave else { return .terminateNow }
        autosave.stop()
        Task {
            await autosave.saveNow()
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

    /// The first Profile of the app database, created on the first launch, and its own database. When a database
    /// cannot be opened, Safira still opens, with Tabs that are not saved.
    private static func openProfile(in layout: StoreLayout) -> (Profile, ProfileDatabase) {
        var profile = defaultProfile
        do {
            let app = try AppDatabase(file: layout.appDatabaseFile)
            if let first = try app.profiles().first {
                profile = first
            } else {
                try app.add(profile)
            }
            return (profile, try ProfileDatabase(file: layout.profileDatabaseFile(for: profile.id)))
        } catch {
            log.error("The databases could not be opened; Tabs will not be saved: \(error, privacy: .private)")
            // An in-memory database cannot fail to open.
            return (profile, try! ProfileDatabase.inMemory())
        }
    }
}
