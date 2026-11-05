// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Diagnostics
import SafiraSession
import SafiraStore
import SafiraWeb
import UniformTypeIdentifiers

/// Debug mode in the app: the switch, the periodic Tab and memory sample, and the manual export from the Help menu.
@MainActor
final class DiagnosticsController: NSObject, NSMenuItemValidation {
    private static let sampleInterval = Duration.seconds(60)

    let logger: DiagnosticLogger
    private let settings = DiagnosticsSettingsStore()
    private weak var registry: ProfileRegistry?
    private var sampling: Task<Void, Never>?

    override init() {
        logger = DiagnosticLogger(subsystem: Bundle.main.bundleIdentifier ?? "com.overlabing.safira",
                                  logsDirectory: StoreLayout.application.logsDirectory)
        super.init()
        logger.setEnabled(settings.load().isDebugModeEnabled)
    }

    func attach(to registry: ProfileRegistry) {
        self.registry = registry
        restartSampling()
    }

    var isDebugModeEnabled: Bool { logger.isEnabled }

    func setDebugMode(_ enabled: Bool) {
        logger.setEnabled(enabled)
        settings.save(DiagnosticsSettings(isDebugModeEnabled: enabled))
        restartSampling()
    }

    @objc func toggleDebugMode(_ sender: Any?) {
        setDebugMode(!logger.isEnabled)
    }

    @objc func exportDiagnosticLogs(_ sender: Any?) {
        guard logger.hasLogs else {
            show(message: String(localized: "There are no diagnostic logs to export", comment: "Alert title"),
                 detail: String(localized: "Turn on Debug mode in the Help menu, use Safira, then export again.",
                                comment: "Alert text, under There are no diagnostic logs to export"))
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        let day = Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        panel.nameFieldStringValue = String(localized: "Safira Diagnostics \(day).zip",
                                            comment: "File name of the diagnostics export; the argument is a date such as 2026-11-05")
        panel.message = String(localized: """
            The archive holds Safira's local diagnostic logs: site hosts, error codes, load times and memory. \
            Nothing is sent anywhere.
            """, comment: "Save panel message of the diagnostics export")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do {
                try await logger.exportArchive(to: destination)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                show(message: String(localized: "The diagnostic logs could not be exported", comment: "Alert title"), detail: error.localizedDescription)
            }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleDebugMode(_:)) {
            menuItem.state = logger.isEnabled ? .on : .off
        }
        return true
    }

    private func restartSampling() {
        sampling?.cancel()
        sampling = nil
        guard logger.isEnabled else { return }
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

    private func show(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}
