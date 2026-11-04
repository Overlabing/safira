// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Darwin
import Foundation

/// Asks whether Safira may read a folder that macOS protects behind a consent prompt, such as Downloads.
enum FolderAccess {
    /// The prompt appears at the first open of the folder and holds the thread that opened it until the user answers.
    /// That thread is never the main one: a prompt left hidden or queued behind another would hang the whole app.
    /// - Parameter probe: what opens the folder; tests replace it to see which thread it runs on.
    static func isAllowed(_ folder: URL, probe: @escaping @Sendable (String) -> Bool = FolderAccess.opens) async -> Bool {
        let path = folder.path(percentEncoded: false)
        return await Task.detached(priority: .userInitiated) { probe(path) }.value
    }

    /// A missing folder is not a refusal: only a permission error is.
    static func opens(_ path: String) -> Bool {
        guard let directory = opendir(path) else { return errno != EPERM && errno != EACCES }
        closedir(directory)
        return true
    }
}

/// Where files go when the user declines access to the Downloads folder.
enum FallbackFolder {
    /// A real folder of the app's own container. It is never the container's `Downloads` entry: macOS makes that one a
    /// symbolic link to the user's real Downloads folder, which is the very folder that was declined.
    static func defaultFolder() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Safira", directoryHint: .isDirectory)
            .appending(path: "Downloads", directoryHint: .isDirectory)
    }

    /// Checks that the folder is a real directory of `container` and not inside `declined`, once every symbolic link is
    /// resolved, then creates it. Nil when it cannot be used, so that nothing is written to the declined folder, not
    /// even an empty directory.
    static func prepare(_ folder: URL, declined: URL, container: URL) -> URL? {
        guard isUsable(resolvedEvenIfMissing(folder), declined: declined, container: container) else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            guard try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { return nil }
        } catch {
            return nil
        }
        let resolved = folder.resolvingSymlinksInPath()
        return isUsable(resolved, declined: declined, container: container) ? resolved : nil
    }

    private static func isUsable(_ resolved: URL, declined: URL, container: URL) -> Bool {
        contains(container.resolvingSymlinksInPath(), resolved) && !contains(declined.resolvingSymlinksInPath(), resolved)
    }

    /// The path with the links of its existing part resolved: a folder that is not there yet cannot be resolved itself.
    private static func resolvedEvenIfMissing(_ folder: URL) -> URL {
        var existing = folder.standardizedFileURL
        var missing: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)), existing.pathComponents.count > 1 {
            missing.insert(existing.lastPathComponent, at: 0)
            existing = existing.deletingLastPathComponent()
        }
        return missing.reduce(existing.resolvingSymlinksInPath()) { $0.appending(path: $1, directoryHint: .isDirectory) }
    }

    private static func contains(_ parent: URL, _ child: URL) -> Bool {
        let parentComponents = parent.standardizedFileURL.pathComponents
        let childComponents = child.standardizedFileURL.pathComponents
        return childComponents.count >= parentComponents.count && Array(childComponents.prefix(parentComponents.count)) == parentComponents
    }
}
