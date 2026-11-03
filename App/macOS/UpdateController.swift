// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Sparkle

/// Sparkle behind two menu items. The updater starts without scheduling any check: `SUEnableAutomaticChecks` is NO in
/// Info.plist, so the first request is either the user's "Check for Updates…" or the user turning the setting on.
@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate, NSMenuItemValidation {
    private var standardController: SPUStandardUpdaterController?

    override init() {
        super.init()
        standardController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    private var updater: SPUUpdater? { standardController?.updater }

    @objc func checkForUpdates(_ sender: Any?) {
        standardController?.checkForUpdates(sender)
    }

    @objc func toggleAutomaticChecks(_ sender: Any?) {
        guard let updater else { return }
        updater.automaticallyChecksForUpdates.toggle()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(checkForUpdates(_:)):
            return updater?.canCheckForUpdates ?? false
        case #selector(toggleAutomaticChecks(_:)):
            item.state = (updater?.automaticallyChecksForUpdates ?? false) ? .on : .off
            return true
        default:
            return true
        }
    }

    #if DEBUG
    /// Lets a Debug build read a local appcast; a Release build always uses the SUFeedURL of Info.plist.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["SAFIRA_UPDATE_FEED_URL"]
    }
    #endif
}
