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

    public func profileDirectory(for profile: ProfileID) -> URL {
        root
            .appending(path: "Profiles", directoryHint: .isDirectory)
            .appending(path: profile.rawValue.uuidString, directoryHint: .isDirectory)
    }
}
