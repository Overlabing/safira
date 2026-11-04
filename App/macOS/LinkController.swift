// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import LinkPickerUI
import LinkRouting
import SafiraCore
import SafiraStore
import SafiraWeb
import UniformTypeIdentifiers

/// `NSRunningApplication` as the Opener lookup. A process that is not an application (the `open` command) has none.
struct WorkspaceApplicationLookup: RunningApplicationLookup {
    func application(processIdentifier: Int32) -> Opener? {
        NSRunningApplication(processIdentifier: processIdentifier).map {
            Opener(bundleIdentifier: $0.bundleIdentifier, name: $0.localizedName)
        }
    }
}

/// `NSWorkspace` as the registry of default applications.
struct WorkspaceDefaultApplications: DefaultApplicationRegistry {
    func defaultApplication(forScheme scheme: String) -> URL? {
        URL(string: "\(scheme)://example.com/").flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
    }

    func setDefaultApplication(toOpenScheme scheme: String) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
    }

    func setDefaultApplication(toOpenContentType identifier: String) async throws {
        guard let type = UTType(identifier) else { return }
        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
    }
}

/// Delivers external links to the Profiles of the app, and shows the Main window once a link has been opened.
@MainActor
private final class RegistryDestination: LinkDestination {
    private let registry: ProfileRegistry
    private let didOpen: @MainActor () -> Void

    init(registry: ProfileRegistry, didOpen: @escaping @MainActor () -> Void) {
        self.registry = registry
        self.didOpen = didOpen
    }

    var profiles: [Profile] { registry.profiles }

    func open(_ url: URL, in profile: ProfileID) -> Bool {
        guard registry.openExternalLink(url, in: profile) else { return false }
        didOpen()
        return true
    }
}

/// External links in the app: the Link picker, the choice log and the default browser setting, with their menu items.
@MainActor
final class LinkController: NSObject, NSMenuItemValidation {
    private let coordinator: ExternalLinkCoordinator
    private let choiceLog: LinkChoiceLog
    private let settings = LinkChoiceLogSettingsStore()
    private let defaultBrowser = DefaultBrowser(registry: WorkspaceDefaultApplications(), appURL: Bundle.main.bundleURL)

    init(registry: ProfileRegistry, mainWindow: MainWindowController) {
        choiceLog = LinkChoiceLog(file: StoreLayout.application.linkChoiceLogFile,
                                  isEnabled: settings.load().isEnabled)
        coordinator = ExternalLinkCoordinator(
            destination: RegistryDestination(registry: registry) { [weak mainWindow] in mainWindow?.showOpenedLink() },
            chooser: LinkPickerPresenter(),
            choiceLog: choiceLog)
        super.init()
    }

    func receive(_ link: IncomingLink) {
        coordinator.receive(link)
    }

    @objc func toggleChoiceLog(_ sender: Any?) {
        choiceLog.isEnabled.toggle()
        settings.save(LinkChoiceLogSettings(isEnabled: choiceLog.isEnabled))
    }

    @objc func makeDefaultBrowser(_ sender: Any?) {
        Task { @MainActor in
            do {
                try await defaultBrowser.makeDefault()
            } catch {
                let alert = NSAlert()
                alert.messageText = String(localized: "Safira could not be made the default browser")
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleChoiceLog(_:)):
            menuItem.state = choiceLog.isEnabled ? .on : .off
            menuItem.toolTip = LinkChoiceLogSettings.explanation
            return true
        case #selector(makeDefaultBrowser(_:)):
            let isDefault = defaultBrowser.isDefault
            menuItem.title = isDefault ? String(localized: "Safira Is the Default Browser")
                                       : String(localized: "Make Safira the Default Browser…")
            return !isDefault
        default:
            return true
        }
    }
}
