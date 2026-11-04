// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Darwin
import Foundation

/// Asks whether Safira may read a folder that macOS protects behind a consent prompt, such as Downloads.
enum FolderAccess {
    /// The prompt appears at the first open of the folder and holds the thread that opened it until the user answers.
    /// That thread is never the main one: a prompt left hidden or queued behind another would hang the whole app.
    static func isAllowed(_ folder: URL) async -> Bool {
        let path = folder.path(percentEncoded: false)
        return await Task.detached(priority: .userInitiated) { opens(path) }.value
    }

    /// A missing folder is not a refusal: only a permission error is.
    static func opens(_ path: String) -> Bool {
        guard let directory = opendir(path) else { return errno != EPERM && errno != EACCES }
        closedir(directory)
        return true
    }
}
