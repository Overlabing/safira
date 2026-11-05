// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Preferences

/// Why Slack's folder was not accepted.
public enum SlackFolderError: Error, Hashable, Sendable {
    /// The folder has no `storage/root-state.json`: it is not the one Slack keeps its workspaces in.
    case notSlackFolder
}

/// The folder of the Slack app that the user grants once. The App Sandbox forbids reading it directly, so the user picks
/// it in an open panel and the choice is kept app-wide as a security-scoped bookmark. Without a grant, no Slack link is
/// rewritten and nothing is reported. The bookmark is kept as the raw bytes it always was, in AppSupportKit's key-value
/// store: a JSON `Preference` would only wrap the same bytes in text.
public struct SlackFolderGrant: SlackWorkspaceLookup, Sendable {
    public static let key = "linkRules.slackFolderBookmark"
    private let store: any KeyValueStore

    public init(store: any KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    public var isGranted: Bool {
        store.data(forKey: Self.key) != nil
    }

    /// Keeps the folder the user picked. Throws when it has no Slack workspace state, and keeps nothing then.
    public func grant(_ folder: URL) throws {
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: Self.stateFile(in: folder).path(percentEncoded: false)) else {
            throw SlackFolderError.notSlackFolder
        }
        store.setData(try folder.bookmarkData(options: .withSecurityScope), forKey: Self.key)
    }

    public func revoke() {
        store.setData(nil, forKey: Self.key)
    }

    public func teamID(forDomain domain: String) -> String? {
        guard let folder = grantedFolder() else { return nil }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: Self.stateFile(in: folder)) else { return nil }
        return Self.teamID(forDomain: domain, inWorkspaceState: data)
    }

    /// The team identifier of the workspace whose Slack domain is `domain` ("acme" for acme.slack.com), from the
    /// contents of Slack's `root-state.json`.
    public static func teamID(forDomain domain: String, inWorkspaceState data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let workspaces = root["workspaces"] as? [String: [String: Any]] else { return nil }
        let wanted = domain.lowercased()
        return workspaces.first { ($0.value["domain"] as? String)?.lowercased() == wanted }?.key
    }

    private func grantedFolder() -> URL? {
        guard let bookmark = store.data(forKey: Self.key) else { return nil }
        var isStale = false
        guard let folder = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                                    bookmarkDataIsStale: &isStale) else { return nil }
        if isStale, let fresh = try? folder.bookmarkData(options: .withSecurityScope) {
            store.setData(fresh, forKey: Self.key)
        }
        return folder
    }

    private static func stateFile(in folder: URL) -> URL {
        folder.appending(path: "storage/root-state.json", directoryHint: .notDirectory)
    }
}
