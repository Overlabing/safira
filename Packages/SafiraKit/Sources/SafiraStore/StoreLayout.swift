// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore

/// Where Safira keeps its files under the app's Application Support folder.
public struct StoreLayout: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// Debug mode's rotating log files; the folder does not exist until Debug mode writes its first line.
    public var logsDirectory: URL {
        root.appending(path: "Logs", directoryHint: .isDirectory)
    }

    /// App-level data: the list of Profiles.
    public var appDatabaseFile: URL {
        root.appending(path: "app.sqlite", directoryHint: .notDirectory)
    }

    /// The Link picker's choice log, when the user turns it on.
    public var linkChoiceLogFile: URL {
        root.appending(path: "link-choices.jsonl", directoryHint: .notDirectory)
    }

    public func profileDirectory(for profile: ProfileID) -> URL {
        root
            .appending(path: "Profiles", directoryHint: .isDirectory)
            .appending(path: profile.rawValue.uuidString, directoryHint: .isDirectory)
    }

    /// Everything a Profile saves lives in this database, inside the Profile's own folder.
    public func profileDatabaseFile(for profile: ProfileID) -> URL {
        profileDirectory(for: profile).appending(path: "profile.sqlite", directoryHint: .notDirectory)
    }
}
