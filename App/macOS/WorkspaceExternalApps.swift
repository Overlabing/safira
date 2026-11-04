// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore
import SafiraSession

/// `NSWorkspace` as the apps a non-web link can open. The link opens in the app the confirmation named, never in
/// another one the system might pick between the question and the answer.
@MainActor
final class WorkspaceExternalApps: ExternalAppLauncher {
    func app(toOpen url: URL) -> ExternalApp? {
        guard let location = NSWorkspace.shared.urlForApplication(toOpen: url) else { return nil }
        return ExternalApp(name: FileManager.default.displayName(atPath: location.path(percentEncoded: false)),
                           location: location)
    }

    func open(_ url: URL, with app: ExternalApp) async throws {
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: app.location,
                                              configuration: NSWorkspace.OpenConfiguration())
    }
}
