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

    @objc func toggleDebugMode(_ sender: Any?) {
        let enabled = !logger.isEnabled
        logger.setEnabled(enabled)
        settings.save(DiagnosticsSettings(isDebugModeEnabled: enabled))
        restartSampling()
    }

    @objc func exportDiagnosticLogs(_ sender: Any?) {
        guard logger.hasLogs else {
            show(message: "There are no diagnostic logs to export",
                 detail: "Turn on Debug mode in the Help menu, use Safira, then export again.")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "Safira Diagnostics \(Date.now.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())).zip"
        panel.message = "The archive holds Safira's local diagnostic logs: site hosts, error codes, load times and memory. "
            + "Nothing is sent anywhere."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do {
                try await logger.exportArchive(to: destination)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                show(message: "The diagnostic logs could not be exported", detail: error.localizedDescription)
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
