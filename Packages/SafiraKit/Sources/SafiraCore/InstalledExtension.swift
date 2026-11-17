// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// A web extension installed for the whole app. It is installed once and runs in every Profile whose switch is on;
/// every Profile's switch is on until the user turns it off. A Private window runs no extension.
public struct InstalledExtension: Hashable, Sendable, Identifiable {
    /// The extension's `uniqueIdentifier`, `browser.runtime.id`: fixed at install and never changed afterwards, so the
    /// extension's pages, storage and the identifier its own app knows stay the same across updates and relaunches.
    public let id: String
    public var source: ExtensionSource
    /// The name and version read from the manifest the last time it was loaded.
    public var displayName: String
    public var version: String
    /// The permissions and match patterns the user allowed, as WebKit spells them (`storage`, `https://*/*`), sorted.
    public var grantedPermissions: [String]
    public var grantedMatchPatterns: [String]
    /// The Profiles where the user turned it off. A Profile created later starts with it on.
    public var disabledProfiles: Set<ProfileID>
    public let installedAt: Date

    public init(id: String, source: ExtensionSource, displayName: String, version: String,
                grantedPermissions: [String], grantedMatchPatterns: [String], disabledProfiles: Set<ProfileID> = [],
                installedAt: Date) {
        self.id = id
        self.source = source
        self.displayName = displayName
        self.version = version
        self.grantedPermissions = grantedPermissions.sorted()
        self.grantedMatchPatterns = grantedMatchPatterns.sorted()
        self.disabledProfiles = disabledProfiles
        self.installedAt = installedAt
    }

    public func isEnabled(in profile: ProfileID) -> Bool {
        !disabledProfiles.contains(profile)
    }
}

/// Where an installed extension's files are.
public enum ExtensionSource: Hashable, Sendable {
    /// A folder the user chose, kept as an app-scope security-scoped bookmark. Safira reads it in place, so the app
    /// that ships the folder updates the extension.
    case folder(bookmark: Data)
    /// A ZIP archive Safira copied into its own folder, named after the identifier; a CRX is stored without its header.
    case archive(fileName: String)
}
