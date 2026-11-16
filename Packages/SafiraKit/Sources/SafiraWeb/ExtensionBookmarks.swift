// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// A folder found again from its bookmark.
public struct ResolvedFolder: Equatable, Sendable {
    public let url: URL
    /// The bookmark still found the folder but should be made again: the folder was replaced or moved.
    public let isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

/// How the folder of an extension installed from a folder is remembered: the sandbox lets Safira read it after a
/// relaunch only through an app-scope security-scoped bookmark of the user's choice.
public protocol ExtensionFolderBookmarks: Sendable {
    func bookmark(for folder: URL) throws -> Data
    func resolve(_ bookmark: Data) throws -> ResolvedFolder
    /// Starts reading the folder; false when the sandbox refuses.
    func startAccessing(_ folder: URL) -> Bool
    func stopAccessing(_ folder: URL)
}

/// Security-scoped bookmarks, as the App Sandbox requires (`files.bookmarks.app-scope`).
public struct SecurityScopedBookmarks: ExtensionFolderBookmarks {
    public init() {}

    public func bookmark(for folder: URL) throws -> Data {
        try folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ bookmark: Data) throws -> ResolvedFolder {
        var isStale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil,
                          bookmarkDataIsStale: &isStale)
        return ResolvedFolder(url: url, isStale: isStale)
    }

    public func startAccessing(_ folder: URL) -> Bool {
        folder.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ folder: URL) {
        folder.stopAccessingSecurityScopedResource()
    }
}
