// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Observation
import SafiraCore
import SafiraStore
import WebKit

/// What the Extensions pane shows of an installed extension besides what is saved: what was read from its files in
/// this run.
public struct ExtensionStatus: Sendable {
    public enum Availability: Sendable, Equatable {
        case available
        /// Its folder or its copy cannot be found: the folder was moved or deleted, or access to it was lost.
        case missing
        /// It was found but WebKit refused to read it.
        case failed(String)
    }

    public var availability: Availability
    public var icon: NSImage?
    /// What WebKit reported while loading it; empty when it had nothing to say.
    public var errors: [String]
    public var hasAccessToAllHosts: Bool

    public init(availability: Availability = .available, icon: NSImage? = nil, errors: [String] = [],
                hasAccessToAllHosts: Bool = false) {
        self.availability = availability
        self.icon = icon
        self.errors = errors
        self.hasAccessToAllHosts = hasAccessToAllHosts
    }
}

/// The extensions installed for the app, and the one place that installs, switches and removes them. Each Profile's
/// host loads the extensions whose switch is on for that Profile; every switch is on until the user turns it off, also
/// for a Profile created later. A Private window has no host, so no extension runs there.
@MainActor
@Observable
public final class ExtensionLibrary {
    /// In the order they were installed.
    public private(set) var installed: [InstalledExtension] = []
    public private(set) var statuses: [String: ExtensionStatus] = [:]
    /// Asks the user to allow what an extension asks for (at install, at an update that asks for more, at run time).
    /// Without it, nothing is installed and no run-time request is allowed.
    @ObservationIgnored public var permissionPrompt: (@MainActor (ExtensionPermissionRequest) async -> Bool)?

    @ObservationIgnored private let database: AppDatabase?
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let bookmarks: any ExtensionFolderBookmarks
    @ObservationIgnored private let storage: WebsiteStorage
    @ObservationIgnored private let onError: @MainActor (String, any Error) -> Void
    @ObservationIgnored private var hosts: [ProfileID: ExtensionHost] = [:]
    /// Every Profile, loaded or not: Remove reaches the data of the ones without a host too.
    @ObservationIgnored var allProfiles: @MainActor () -> [ProfileID] = { [] }
    /// The folders read through their bookmark, by extension, until the extension is removed.
    @ObservationIgnored private var accessedFolders: [String: URL] = [:]

    /// - Parameters:
    ///   - database: where the list is saved; nil keeps it for this run only.
    ///   - directory: where copies of ZIP and CRX installs go.
    ///   - storage: `.inMemory` when the Profiles' extension state is non-persistent, as in tests.
    public init(database: AppDatabase?, directory: URL, bookmarks: any ExtensionFolderBookmarks = SecurityScopedBookmarks(),
                storage: WebsiteStorage = .onDisk, onError: @escaping @MainActor (String, any Error) -> Void = { _, _ in }) {
        self.database = database
        self.directory = directory
        self.bookmarks = bookmarks
        self.storage = storage
        self.onError = onError
        do {
            installed = try database?.installedExtensions() ?? []
        } catch {
            onError("The installed extensions could not be read", error)
        }
        for item in installed {
            statuses[item.id] = ExtensionStatus(availability: resource(of: item) == nil ? .missing : .available)
        }
        Task { await readDetails() }
    }

    // MARK: Profiles

    /// Loads into a Profile's host every extension whose switch is on for that Profile.
    func attach(_ host: ExtensionHost, profile: ProfileID) async {
        hosts[profile] = host
        host.permissionRequests = { [weak self] request in
            await self?.allowAtRuntime(request) ?? false
        }
        for item in installed where item.isEnabled(in: profile) {
            await load(item, into: host)
        }
    }

    func detach(profile: ProfileID) {
        hosts[profile] = nil
    }

    // MARK: Installing

    /// Installs the extension in a folder (holding `manifest.json`), a `.zip` or a `.crx` file, after the user allows
    /// what it asks for. It is then on in every Profile. Returns nil when the user cancelled, and nothing is installed.
    /// - Parameter prompt: asks the user; `permissionPrompt` unless given.
    @discardableResult
    public func install(from url: URL,
                        prompt: (@MainActor (ExtensionPermissionRequest) async -> Bool)? = nil) async throws -> InstalledExtension? {
        let package = try ExtensionPackage.read(url)
        let resource: URL
        var crxIdentifier: String?
        var staged: URL?
        switch package {
        case .folder(let folder):
            resource = folder
        case .zip(let data), .crx(let data, _):
            if case .crx(_, let identifier) = package { crxIdentifier = identifier }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appending(path: "staging-\(UUID().uuidString).zip", directoryHint: .notDirectory)
            try data.write(to: file)
            staged = file
            resource = file
        }
        defer { if let staged { try? FileManager.default.removeItem(at: staged) } }

        let webExtension = try await WKWebExtension(resourceBaseURL: resource)
        let id = ExtensionIdentity.identifier(forManifest: webExtension.manifest, crxIdentifier: crxIdentifier)
        if let existing = installed.first(where: { $0.id == id }) {
            throw ExtensionInstallError.alreadyInstalled(name: existing.displayName)
        }
        let request = ExtensionPermissionRequest(webExtension, id: id, moment: .install)
        guard let ask = prompt ?? permissionPrompt, await ask(request) else { return nil }

        let source: ExtensionSource
        if let staged {
            let fileName = "\(id).zip"
            let destination = directory.appending(path: fileName, directoryHint: .notDirectory)
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: staged, to: destination)
            source = .archive(fileName: fileName)
        } else {
            source = .folder(bookmark: try bookmarks.bookmark(for: resource))
        }
        let item = InstalledExtension(id: id, source: source, displayName: webExtension.displayName ?? id,
                                      version: webExtension.version ?? "", grantedPermissions: request.permissions,
                                      grantedMatchPatterns: request.matchPatterns, installedAt: Date())
        save(item)
        installed.append(item)
        statuses[id] = ExtensionStatus(icon: request.icon, hasAccessToAllHosts: request.hasAccessToAllHosts)
        for (profile, host) in hosts where item.isEnabled(in: profile) {
            await load(item, into: host)
        }
        return item
    }

    // MARK: Switching and removing

    /// Turns an extension on or off in one Profile. Off, it stops there at once and its stored data is kept.
    public func setEnabled(_ enabled: Bool, extension id: String, in profile: ProfileID) async {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        if enabled {
            installed[index].disabledProfiles.remove(profile)
        } else {
            installed[index].disabledProfiles.insert(profile)
        }
        let item = installed[index]
        save(item)
        guard let host = hosts[profile] else { return }
        if enabled {
            await load(item, into: host)
        } else {
            host.unload(id)
        }
    }

    /// Removes an extension from the app: it stops in every Profile, what it stored in each Profile is deleted, then
    /// its bookmark or its copy.
    public func remove(_ id: String) async {
        guard let item = installed.first(where: { $0.id == id }) else { return }
        for host in hosts.values {
            await host.removeData(of: id)
            host.unload(id)
        }
        if storage == .onDisk {
            for profile in allProfiles() where hosts[profile] == nil {
                await ExtensionHost.removeData(of: id, inProfile: profile)
            }
        }
        if let folder = accessedFolders.removeValue(forKey: id) {
            bookmarks.stopAccessing(folder)
        }
        if case .archive(let fileName) = item.source {
            let file = directory.appending(path: fileName, directoryHint: .notDirectory)
            do {
                if FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: file)
                }
            } catch {
                onError("The extension's copy could not be deleted", error)
            }
        }
        do {
            try database?.deleteInstalledExtension(id)
        } catch {
            onError("The removed extension could not be forgotten", error)
        }
        installed.removeAll { $0.id == id }
        statuses[id] = nil
    }

    // MARK: Folders

    /// Points an extension whose folder cannot be found at the folder the user found it in. A folder holding another
    /// extension (another manifest `key`) is refused.
    public func locate(_ id: String, at folder: URL) async throws {
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        guard case .folder(let found) = try ExtensionPackage.read(folder) else {
            throw ExtensionInstallError.unsupportedFile(name: folder.lastPathComponent)
        }
        let webExtension = try await WKWebExtension(resourceBaseURL: found)
        if let keyed = ExtensionIdentity.identifier(forManifestKey: webExtension.manifest["key"] as? String), keyed != id {
            throw ExtensionInstallError.differentExtension(name: installed[index].displayName)
        }
        installed[index].source = .folder(bookmark: try bookmarks.bookmark(for: found))
        save(installed[index])
        statuses[id] = ExtensionStatus()
        if let previous = accessedFolders.removeValue(forKey: id) { bookmarks.stopAccessing(previous) }
        try await reload(id, force: true)
    }

    /// Reads the manifest of every extension installed from a folder again, and reloads in every Profile those whose
    /// version changed, under the same identifier. An update that asks for more is asked about once; what the user does
    /// not allow stays off. A folder replaced in place (an app update) is found again through its bookmark.
    public func checkForUpdates() async {
        for item in installed {
            guard case .folder = item.source else { continue }
            do {
                try await reload(item.id, force: false)
            } catch {
                onError("An extension could not be updated", error)
            }
        }
    }

    // MARK: Private

    private func reload(_ id: String, force: Bool) async throws {
        guard let item = installed.first(where: { $0.id == id }) else { return }
        guard let resource = resource(of: item) else {
            statuses[id, default: ExtensionStatus()].availability = .missing
            return
        }
        if !force {
            guard let version = Self.manifestVersion(in: resource), version != item.version else { return }
        }
        let webExtension = try await WKWebExtension(resourceBaseURL: resource)
        var updated = item
        updated.displayName = webExtension.displayName ?? item.displayName
        updated.version = webExtension.version ?? item.version
        let granted = InstalledGrants(permissions: Set(item.grantedPermissions), matchPatterns: Set(item.grantedMatchPatterns))
        let request = ExtensionPermissionRequest(webExtension, id: id, moment: .update, alreadyGranted: granted)
        if !request.isEmpty, let ask = permissionPrompt, await ask(request) {
            updated.grantedPermissions = (item.grantedPermissions + request.permissions).sorted()
            updated.grantedMatchPatterns = (item.grantedMatchPatterns + request.matchPatterns).sorted()
        }
        guard let index = installed.firstIndex(where: { $0.id == id }) else { return }
        installed[index] = updated
        save(updated)
        statuses[id] = ExtensionStatus(icon: webExtension.icon(for: CGSize(width: 64, height: 64)),
                                       hasAccessToAllHosts: Self.reachesAllHosts(updated))
        for (profile, host) in hosts where updated.isEnabled(in: profile) {
            host.unload(id)
            await load(updated, into: host)
        }
    }

    private func load(_ item: InstalledExtension, into host: ExtensionHost) async {
        guard let resource = resource(of: item) else {
            statuses[item.id, default: ExtensionStatus()].availability = .missing
            return
        }
        do {
            let loaded = try await host.load(item, from: resource)
            statuses[item.id, default: ExtensionStatus()].errors = loaded.errors
        } catch {
            statuses[item.id, default: ExtensionStatus()].availability = .failed(error.localizedDescription)
        }
    }

    /// Where an installed extension's files are now: its folder, found again through its bookmark (made again when
    /// the folder was replaced), or its copy. Nil when they cannot be found.
    private func resource(of item: InstalledExtension) -> URL? {
        switch item.source {
        case .archive(let fileName):
            let file = directory.appending(path: fileName, directoryHint: .notDirectory)
            return FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? file : nil
        case .folder(let bookmark):
            let resolved: ResolvedFolder
            do {
                resolved = try bookmarks.resolve(bookmark)
            } catch {
                return nil
            }
            if accessedFolders[item.id] != resolved.url {
                if let previous = accessedFolders[item.id] { bookmarks.stopAccessing(previous) }
                // Outside the sandbox there is nothing to start, and the folder is readable anyway.
                _ = bookmarks.startAccessing(resolved.url)
                accessedFolders[item.id] = resolved.url
            }
            let manifest = resolved.url.appending(path: "manifest.json", directoryHint: .notDirectory)
            guard FileManager.default.fileExists(atPath: manifest.path(percentEncoded: false)) else { return nil }
            if resolved.isStale, let fresh = try? bookmarks.bookmark(for: resolved.url),
               let index = installed.firstIndex(where: { $0.id == item.id }) {
                installed[index].source = .folder(bookmark: fresh)
                save(installed[index])
            }
            return resolved.url
        }
    }

    /// Reads the icons and what WebKit says of each extension once, for the Extensions pane.
    private func readDetails() async {
        for item in installed {
            guard let resource = resource(of: item),
                  let webExtension = try? await WKWebExtension(resourceBaseURL: resource) else { continue }
            statuses[item.id, default: ExtensionStatus()].icon = webExtension.icon(for: CGSize(width: 64, height: 64))
            statuses[item.id, default: ExtensionStatus()].hasAccessToAllHosts = Self.reachesAllHosts(item)
        }
    }

    private func allowAtRuntime(_ request: ExtensionPermissionRequest) async -> Bool {
        guard let permissionPrompt, await permissionPrompt(request),
              let index = installed.firstIndex(where: { $0.id == request.extensionID }) else { return false }
        var item = installed[index]
        item.grantedPermissions = Array(Set(item.grantedPermissions).union(request.permissions)).sorted()
        item.grantedMatchPatterns = Array(Set(item.grantedMatchPatterns).union(request.matchPatterns)).sorted()
        installed[index] = item
        save(item)
        statuses[item.id, default: ExtensionStatus()].hasAccessToAllHosts = Self.reachesAllHosts(item)
        let grants = InstalledGrants(permissions: Set(request.permissions), matchPatterns: Set(request.matchPatterns))
        for host in hosts.values { host.grant(grants, to: item.id) }
        return true
    }

    private func save(_ item: InstalledExtension) {
        do {
            try database?.save(item)
        } catch {
            onError("The installed extension could not be saved", error)
        }
    }

    private static func reachesAllHosts(_ item: InstalledExtension) -> Bool {
        item.grantedMatchPatterns.contains { pattern in
            guard let matchPattern = try? WKWebExtension.MatchPattern(string: pattern) else { return false }
            return matchPattern.matchesAllHosts || matchPattern.matchesAllURLs
        }
    }

    /// The `version` of a folder's manifest, read without WebKit, so that checking for updates parses nothing else.
    static func manifestVersion(in folder: URL) -> String? {
        let file = folder.appending(path: "manifest.json", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: file),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return manifest["version"] as? String
    }
}
