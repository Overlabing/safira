// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Diagnostics
import DiagnosticsKit
import SafiraSession
import SafiraStore
import SafiraWeb
import UniformTypeIdentifiers

/// Debug mode in the app: the switch, the periodic Tab and memory sample, and the manual export from the Help menu.
@MainActor
final class DiagnosticsController: NSObject, NSMenuItemValidation {
    private static let sampleInterval = Duration.seconds(60)

    let log: DiagnosticLog
    let logger: DiagnosticLogger
    private let settings = DiagnosticsSettingsStore()
    private weak var registry: ProfileRegistry?
    private var sampling: Task<Void, Never>?
    /// What greys out the export: read from the log after every write, since a menu cannot wait for it.
    private var hasLogs = false

    init(preferenceProblems: PreferenceProblems) {
        log = DiagnosticLog(configuration: .safira(subsystem: Bundle.main.bundleIdentifier ?? "com.overlabing.safira"),
                            isEnabled: false)
        logger = DiagnosticLogger(category: "navigation", sink: log)
        super.init()
        let directory = StoreLayout.application.logsDirectory
        // On the writer's queue, before the kit's first prune: the old-format files hold site hosts.
        log.start {
            LegacyLogFiles.remove(in: directory)
            return directory
        }
        log.observeSize { [weak self] _ in
            Task { @MainActor in await self?.refreshHasLogs() }
        }
        logger.setDebugMode(settings.load(unreadable: preferenceProblems.record).isDebugModeEnabled)
    }

    func attach(to registry: ProfileRegistry) {
        self.registry = registry
        restartSampling()
    }

    var isDebugModeEnabled: Bool { log.isEnabled }

    func setDebugMode(_ enabled: Bool) {
        logger.setDebugMode(enabled)
        settings.save(DiagnosticsSettings(isDebugModeEnabled: enabled))
        restartSampling()
    }

    @objc func toggleDebugMode(_ sender: Any?) {
        setDebugMode(!log.isEnabled)
    }

    @objc func exportDiagnosticLogs(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        let day = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        panel.nameFieldStringValue = String(localized: "Safira Diagnostics \(day).zip",
                                            comment: "File name of the diagnostics export; the argument is a date such as 2026-11-05")
        panel.message = String(localized: """
            The archive holds Safira's local diagnostic logs: error codes, load times, Tab counts and memory. It names \
            no site: no host, address or page title. Nothing is sent anywhere.
            """, comment: "Save panel message of the diagnostics export")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do {
                try await log.export(environment: Self.environment, requireLogs: true, to: destination)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch DiagnosticArchiveError.noLogs {
                UserFacingAlert.runModal(.noDiagnosticLogs)
            } catch {
                UserFacingAlert.runModal(.diagnosticLogsNotExported(error))
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleDebugMode(_:)) {
            menuItem.state = log.isEnabled ? .on : .off
        }
        if menuItem.action == #selector(exportDiagnosticLogs(_:)) {
            return hasLogs
        }
        return true
    }

    private func refreshHasLogs() async {
        hasLogs = (try? await log.hasLogs()) ?? false
    }

    private static var environment: String {
        let info = Bundle.main.infoDictionary
        return DiagnosticEnvironment.text(appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
                                          build: info?["CFBundleVersion"] as? String ?? "?",
                                          system: ProcessInfo.processInfo.operatingSystemVersion)
    }

    private func restartSampling() {
        sampling?.cancel()
        sampling = nil
        guard log.isEnabled else { return }
        sampling = Task { [weak self] in
            while !Task.isCancelled {
                self?.sample()
                try? await Task.sleep(for: Self.sampleInterval)
            }
        }
    }

    private func sample() {
        if let registry {
            let counts = registry.loadedContexts.map(\.session.diagnosticTabCounts)
            logger.record(.tabCounts(TabCounts(blank: counts.map(\.blank).reduce(0, +),
                                               loading: counts.map(\.loading).reduce(0, +),
                                               loaded: counts.map(\.loaded).reduce(0, +))))
        }
        if let bytes = ProcessFootprint.currentBytes() {
            logger.record(.memory(footprintBytes: bytes))
        }
    }
}
