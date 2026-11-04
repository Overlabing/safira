// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Commands
import LinkRouting
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
    private var links: LinkController?
    /// Links that arrived before the Profiles were open, as on a launch started by a link.
    private var earlyLinks: [IncomingLink] = []
    private let openers = OpenerIdentifier(lookup: WorkspaceApplicationLookup(),
                                           ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier)
    #if BENCHMARK
    private var benchmark: BenchmarkRun?
    #endif

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The Apple event that carries a clicked link, and its sender, is read here: `application(_:open:)` does not
        // give the sender, and a launch started by a link delivers the event right after this.
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleGetURL(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let registry = ProfileRegistry(layout: .application, diagnostics: diagnostics.logger) { message, error in
            Self.log.error("\(message, privacy: .public): \(error, privacy: .private)")
        }
        self.registry = registry
        diagnostics.attach(to: registry)
        let controller = MainWindowController(registry: registry, shortcuts: shortcuts)
        controller.showWindow(nil)
        mainWindow = controller
        let links = LinkController(registry: registry, mainWindow: controller, diagnostics: diagnostics)
        self.links = links
        earlyLinks.forEach(links.receive)
        earlyLinks = []
        rebuildMenu()
        keepMenuInStepWithShortcuts()
        #if BENCHMARK
        // A measurement run leaves the foreground to whatever the user is doing, and opens its addresses in the
        // Active Profile like any other launch.
        if let run = BenchmarkRun(statusDirectory: StoreLayout.application.root) {
            benchmark = run
            run.start(session: registry.active.session)
            return
        }
        #endif
        controller.focusCommandBar(nil)
        NSApp.activate()
    }

    func rebuildMenu() {
        guard let links else { return }
        NSApp.mainMenu = MainMenu.make(updates: updates, diagnostics: diagnostics, links: links,
                                       shortcuts: shortcuts.bindings, shortcutsWindow: shortcutsWindow)
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

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let address = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: address) else { return }
        receive([url], event: event)
    }

    /// Local files (a double-clicked .html, `open page.html`) arrive as an "open documents" event, not a GetURL one.
    func application(_ application: NSApplication, open urls: [URL]) {
        receive(urls, event: NSAppleEventManager.shared().currentAppleEvent)
    }

    private func receive(_ urls: [URL], event: NSAppleEventDescriptor?) {
        let sender = event?.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        let opener = openers.identify(senderProcessIdentifier: sender)
        for url in urls {
            let link = IncomingLink(url: url, opener: opener)
            if let links { links.receive(link) } else { earlyLinks.append(link) }
        }
    }

    /// Quitting stops the running downloads, so that they can be continued, and waits for the last save of every
    /// Profile's Tabs, settings and downloads.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let registry else { return .terminateNow }
        Task {
            await registry.stopDownloads()
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
