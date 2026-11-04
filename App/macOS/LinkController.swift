// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Diagnostics
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

/// `NSWorkspace` as the installed apps of Slack, Linear, Notion and Figma, and the way to open a link in one.
struct WorkspaceNativeApplications: NativeApplications {
    func isInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func open(_ url: URL, bundleIdentifier: String) async -> Bool {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return false }
        do {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            return true
        } catch {
            return false
        }
    }
}

/// Writes what the router could not use to the diagnostics, and tells the user once per change of the rules file that it
/// is invalid.
@MainActor
private final class LinkRulesReporter: LinkRoutingReporting {
    private let logger: DiagnosticLogger
    private let rulesFile: URL
    private var lastAlerted: (error: LinkRulesError, modified: Date?)?

    init(logger: DiagnosticLogger, rulesFile: URL) {
        self.logger = logger
        self.rulesFile = rulesFile
    }

    func rulesFileIsInvalid(_ error: LinkRulesError) {
        logger.record(.linkRulesInvalid(Self.problem(for: error)))
        let modified = try? rulesFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let lastAlerted, lastAlerted.error == error, lastAlerted.modified == modified { return }
        lastAlerted = (error, modified)
        let alert = NSAlert()
        alert.messageText = String(localized: "The Link rules file is not valid")
        alert.informativeText = error.explanation + " "
            + String(localized: "No Link rule applies until it is fixed: links go to the Link picker.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Show in Finder"))
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([rulesFile])
        }
    }

    func ruleWasSkipped(index: Int, because problem: LinkRuleProblem) {
        let reason: LinkRuleSkipReason = switch problem {
        case .unknownProfile: .unknownProfile
        case .ambiguousProfile: .ambiguousProfile
        case .unknownSpace: .unknownSpace
        case .ambiguousSpace: .ambiguousSpace
        }
        logger.record(.linkRuleSkipped(index: index, reason: reason))
    }

    private static func problem(for error: LinkRulesError) -> LinkRulesFileProblem {
        switch error {
        case .unreadable: .unreadable
        case .notJSON: .notJSON
        case .unsupportedVersion: .unsupportedVersion
        case .invalidField: .invalidField
        }
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

    func spaces(in profile: ProfileID) -> [SpaceChoice] {
        registry.spaces(in: profile).map { SpaceChoice(id: $0.id, name: $0.name, emoji: $0.emoji) }
    }

    func open(_ url: URL, in target: LinkTarget) -> Bool {
        guard registry.openExternalLink(url, in: target.profile, space: target.space) else { return false }
        didOpen()
        return true
    }

    func matchingTab(for address: NormalizedAddress, in profile: ProfileID) -> MatchingTab? {
        registry.matchingTab(for: address, in: profile)
    }

    func focus(_ match: MatchingTab, openedFrom link: URL) -> Bool {
        guard registry.focus(match, openedFrom: link) else { return false }
        didOpen()
        return true
    }
}

/// External links in the app: the Link picker, the Link rules, the choice log and the default browser setting, with
/// their menu items.
@MainActor
final class LinkController: NSObject, NSMenuItemValidation {
    private var coordinator: ExternalLinkCoordinator!
    private let choiceLog: LinkChoiceLog
    private let settings = LinkChoiceLogSettingsStore()
    private let askForSpaceStore = AskForSpaceSettingsStore()
    private var asksForSpace: Bool
    private let matchingStore = MatchingTabSettingsStore()
    private var matchesOpenTabs: Bool
    private let slackGrant = SlackFolderGrant()
    private let rulesFile = StoreLayout.application.linkRulesFile
    private lazy var rulesStore = LinkRulesStore(url: rulesFile)
    private let registry: ProfileRegistry
    private var rulesWindow: LinkRulesWindowController?
    private let defaultBrowser = DefaultBrowser(registry: WorkspaceDefaultApplications(), appURL: Bundle.main.bundleURL)

    init(registry: ProfileRegistry, mainWindow: MainWindowController, diagnostics: DiagnosticsController) {
        self.registry = registry
        choiceLog = LinkChoiceLog(file: StoreLayout.application.linkChoiceLogFile,
                                  isEnabled: settings.load().isEnabled)
        asksForSpace = askForSpaceStore.load().isEnabled
        matchesOpenTabs = matchingStore.load().isEnabled
        let applications = WorkspaceNativeApplications()
        super.init()
        let router = LinkRouter(
            rules: LinkRulesFile(url: rulesFile),
            nativeApps: NativeAppLinks(applications: applications, slack: slackGrant),
            reporter: LinkRulesReporter(logger: diagnostics.logger, rulesFile: rulesFile),
            isMatchingEnabled: { [weak self] in self?.matchesOpenTabs ?? true })
        coordinator = ExternalLinkCoordinator(
            destination: RegistryDestination(registry: registry) { [weak mainWindow] in mainWindow?.showOpenedLink() },
            chooser: LinkPickerPresenter(), router: router, nativeApplications: applications, choiceLog: choiceLog,
            rememberer: StoredLinkRuleRemembering(
                store: LinkRulesStore(url: rulesFile), didFail: { Self.alertRuleNotSaved($0) },
                didAdd: { [weak self] in self?.rulesWindow?.model.reload() }),
            asksForSpace: { [weak self] in self?.asksForSpace ?? false })
    }

    func receive(_ link: IncomingLink) {
        coordinator.receive(link)
    }

    var logsChoices: Bool {
        get { choiceLog.isEnabled }
        set {
            choiceLog.isEnabled = newValue
            settings.save(LinkChoiceLogSettings(isEnabled: newValue))
        }
    }

    var focusesMatchingTab: Bool {
        get { matchesOpenTabs }
        set {
            matchesOpenTabs = newValue
            matchingStore.save(MatchingTabSettings(isEnabled: newValue))
        }
    }

    var asksForSpaceToo: Bool {
        get { asksForSpace }
        set {
            asksForSpace = newValue
            askForSpaceStore.save(AskForSpaceSettings(isEnabled: newValue))
        }
    }

    var isDefaultBrowser: Bool { defaultBrowser.isDefault }

    @objc func toggleChoiceLog(_ sender: Any?) {
        logsChoices.toggle()
    }

    @objc func toggleMatchingTabs(_ sender: Any?) {
        focusesMatchingTab.toggle()
    }

    @objc func toggleAskForSpace(_ sender: Any?) {
        asksForSpaceToo.toggle()
    }

    /// Slack's own folder, which the sandbox hides: the user picks it once, and Slack links then open in the app.
    @objc func grantSlackFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = Self.slackFolderSuggestion
        panel.message = String(localized: "Choose Slack's folder (Application Support/Slack) so Slack links can open in the Slack app. Safira reads only the list of your workspaces from it.")
        panel.prompt = String(localized: "Grant Access")
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            try slackGrant.grant(folder)
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "That is not Slack's folder")
            alert.informativeText = String(localized: "Choose the folder named Slack inside Application Support. It holds a folder named storage.")
            alert.runModal()
        }
    }

    @objc func forgetSlackFolder(_ sender: Any?) {
        slackGrant.revoke()
    }

    /// The Link rules window, built on first use around the router the real links go through.
    @objc func showLinkRulesWindow(_ sender: Any?) {
        if rulesWindow == nil {
            let registry = registry
            let coordinator = coordinator!
            let model = LinkRulesModel(
                store: rulesStore, profiles: { registry.profiles },
                spacesOf: { id in registry.spaces(in: id).map { SpaceChoice(id: $0.id, name: $0.name, emoji: $0.emoji) } },
                route: { coordinator.route(for: $0) })
            rulesWindow = LinkRulesWindowController(model: model, rulesFile: rulesFile, profiles: { registry.profiles })
        }
        rulesWindow?.show(sender)
    }

    private static func alertRuleNotSaved(_ error: LinkRulesEditError) {
        let alert = NSAlert()
        alert.messageText = String(localized: "The Link rule was not saved")
        alert.informativeText = error.explanation + " " + String(localized: "The link opened where you chose.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    /// The file is made on first use, so there is something to edit.
    @objc func showLinkRules(_ sender: Any?) {
        let manager = FileManager.default
        if !manager.fileExists(atPath: rulesFile.path(percentEncoded: false)) {
            try? manager.createDirectory(at: rulesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("{\n  \"version\": 1,\n  \"rules\": []\n}\n".utf8).write(to: rulesFile)
        }
        NSWorkspace.shared.activateFileViewerSelecting([rulesFile])
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
        case #selector(toggleMatchingTabs(_:)):
            menuItem.state = matchesOpenTabs ? .on : .off
            menuItem.toolTip = MatchingTabSettings.explanation
            return true
        case #selector(toggleAskForSpace(_:)):
            menuItem.state = asksForSpace ? .on : .off
            menuItem.toolTip = AskForSpaceSettings.explanation
            return true
        case #selector(grantSlackFolder(_:)):
            menuItem.title = slackGrant.isGranted ? String(localized: "Change Slack Folder…")
                                                  : String(localized: "Grant Access to Slack's Folder…")
            return true
        case #selector(forgetSlackFolder(_:)):
            return slackGrant.isGranted
        case #selector(makeDefaultBrowser(_:)):
            let isDefault = defaultBrowser.isDefault
            menuItem.title = isDefault ? String(localized: "Safira Is the Default Browser")
                                       : String(localized: "Make Safira the Default Browser…")
            return !isDefault
        default:
            return true
        }
    }

    /// The real home folder: inside the sandbox, the user's home is not the one the process sees.
    private static var slackFolderSuggestion: URL? {
        guard let entry = getpwuid(getuid()) else { return nil }
        return URL(filePath: String(cString: entry.pointee.pw_dir), directoryHint: .isDirectory)
            .appending(path: "Library/Application Support/Slack", directoryHint: .isDirectory)
    }
}
