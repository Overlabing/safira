// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation
import Observation
import SafiraCore
import SafiraSession
import SafiraStore

/// The Profiles of the app, in sidebar order, and the Active profile. It alone creates and deletes Profile owners. A
/// Profile's owner is created the first time it is shown, so the Tabs of a Profile not shown since launch get no page
/// until then; once created, an inactive Profile's Tabs keep running.
@MainActor
@Observable
public final class ProfileRegistry {
    /// Never empty.
    public private(set) var profiles: [Profile]
    public private(set) var activeProfileID: ProfileID
    @ObservationIgnored private var contexts: [ProfileID: ProfileContext] = [:]
    @ObservationIgnored private let appDatabase: AppDatabase?
    @ObservationIgnored private let layout: StoreLayout?
    @ObservationIgnored private let diagnostics: DiagnosticLogger?
    @ObservationIgnored private let onError: @MainActor (String, any Error) -> Void
    @ObservationIgnored private let dataStoreRemovalAttempts: Int

    /// The Profile a first launch starts with. It has no search engine: the Command bar asks at the first search.
    public static let firstProfileName = "Default"

    /// Opens the Profiles listed in `app.sqlite` under `layout`, creating the first one when none is listed, and
    /// finishes erasing the Profiles whose deletion was cut short. When the app database cannot be opened, Safira still
    /// runs with one Profile whose Tabs are not saved.
    /// - Parameter dataStoreRemovalAttempts: tries, 100 ms apart, before giving up on erasing a data store WebKit
    ///   still holds; an erase given up on is finished at the next launch.
    public init(layout: StoreLayout?, diagnostics: DiagnosticLogger? = nil, dataStoreRemovalAttempts: Int = 100,
                onError: @escaping @MainActor (String, any Error) -> Void = { _, _ in }) {
        self.diagnostics = diagnostics
        self.onError = onError
        self.dataStoreRemovalAttempts = dataStoreRemovalAttempts
        var app: AppDatabase?
        var profiles: [Profile] = []
        var active: ProfileID?
        var pending: [ProfileID] = []
        if let layout {
            do {
                let database = try AppDatabase(file: layout.appDatabaseFile)
                profiles = try database.profiles()
                if profiles.isEmpty {
                    let first = Profile(id: ProfileID(rawValue: UUID()), name: Self.firstProfileName)
                    try database.add(first)
                    profiles = [first]
                }
                active = try database.lastActiveProfileID()
                pending = try database.profilesPendingDeletion()
                app = database
            } catch {
                onError("The list of Profiles could not be opened; Tabs will not be saved", error)
                profiles = []
            }
        }
        if app == nil {
            profiles = [Profile(id: ProfileID(rawValue: UUID()), name: Self.firstProfileName)]
        }
        appDatabase = app
        self.layout = app == nil ? nil : layout
        self.profiles = profiles
        activeProfileID = active.flatMap { id in profiles.first { $0.id == id }?.id } ?? profiles[0].id
        for id in pending {
            Task { try? await self.erase(id) }
        }
    }

    public var activeProfile: Profile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    /// The Active profile's owner: the Command bar, search and every Tab command reach this Profile only.
    public var active: ProfileContext {
        context(for: activeProfileID)
    }

    /// The owners created so far, Active profile included.
    public var loadedContexts: [ProfileContext] {
        profiles.compactMap { contexts[$0.id] }
    }

    // MARK: Switching

    /// Shows a Profile in the Main window. Its owner is created, and its selected Tab loaded, the first time.
    public func selectProfile(_ id: ProfileID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        _ = active
        remember(id)
    }

    /// Shows the Profile `offset` places away from the active one, wrapping around the ends of the list.
    public func selectProfile(offset: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        let count = profiles.count
        selectProfile(profiles[((index + offset) % count + count) % count].id)
    }

    /// The Spaces of a Profile, in sidebar order; empty for a Profile that does not exist. This creates the Profile's
    /// owner if it has none yet, without showing the Profile.
    public func spaces(in id: ProfileID) -> [Space] {
        guard profiles.contains(where: { $0.id == id }) else { return [] }
        return context(for: id).session.spaces
    }

    /// Opens a link from another app as a new Tab in a Space of the Profile, or in its last active Space when `space`
    /// is nil, and shows that Profile. The Tab is made by the Profile's own owner, so the link reaches that Profile's
    /// logins and nothing else. False, and nothing changes, when the Profile does not exist or has no such Space.
    @discardableResult
    public func openExternalLink(_ url: URL, in id: ProfileID, space: SpaceID? = nil) -> Bool {
        guard profiles.contains(where: { $0.id == id }) else { return false }
        if let space, !context(for: id).session.spaces.contains(where: { $0.id == space }) { return false }
        selectProfile(id)
        let session = active.session
        if let space { session.selectSpace(space) }
        session.openExternalLink(url)
        return true
    }

    // MARK: Creating and renaming

    /// Adds a Profile after the others and shows it. A Profile cannot be created without a search engine, which the
    /// user picks with nothing preselected. Its identifier is new, so it starts with an empty data store.
    @discardableResult
    public func createProfile(name: String, symbol: String, searchEngine: SearchEngine) -> ProfileID {
        let profile = Profile(id: ProfileID(rawValue: UUID()), name: Self.cleanName(name) ?? Self.firstProfileName,
                              symbol: Self.cleanSymbol(symbol) ?? Profile.defaultSymbol)
        let settings = ProfileSettings(searchEngine: searchEngine)
        do {
            try appDatabase?.add(profile)
        } catch {
            onError("The new Profile could not be saved", error)
        }
        profiles.append(profile)
        contexts[profile.id] = makeContext(profile.id, settings: settings)
        selectProfile(profile.id)
        return profile.id
    }

    /// Renames a Profile. A blank name or symbol keeps the current one; a symbol keeps its first character only.
    public func renameProfile(_ id: ProfileID, name: String, symbol: String) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        if let name = Self.cleanName(name) { profiles[index].name = name }
        if let symbol = Self.cleanSymbol(symbol) { profiles[index].symbol = symbol }
        do {
            try appDatabase?.update(profiles[index])
        } catch {
            onError("The Profile could not be renamed", error)
        }
    }

    // MARK: Deleting

    public var canDeleteProfile: Bool {
        profiles.count > 1
    }

    /// Deletes a Profile and erases everything it holds: its Spaces, Tabs, settings, logins and website data, with no
    /// way back. The last Profile cannot be deleted. Deleting the Active profile shows the one before it, or the next
    /// one when it was first. Returns once the Profile's folder and data store are erased; when WebKit keeps the data
    /// store too long, it throws and the erase is finished at the next launch.
    public func deleteProfile(_ id: ProfileID) async throws {
        guard canDeleteProfile, let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        if activeProfileID == id {
            selectProfile(profiles[index == 0 ? 1 : index - 1].id)
        }
        try appDatabase?.markForDeletion(id)
        profiles.remove(at: index)
        contexts.removeValue(forKey: id)?.discard()
        try await erase(id)
    }

    /// Saves every Profile now and waits until the writes have reached their databases.
    public func saveAll() async {
        for context in loadedContexts {
            await context.saveNow()
        }
    }

    // MARK: Private

    private func context(for id: ProfileID) -> ProfileContext {
        if let context = contexts[id] { return context }
        let context = makeContext(id, settings: nil)
        contexts[id] = context
        return context
    }

    private func makeContext(_ id: ProfileID, settings: ProfileSettings?) -> ProfileContext {
        let database = database(for: id)
        if let settings {
            do {
                try database.save(settings)
            } catch {
                onError("The new Profile's settings could not be saved", error)
            }
        }
        return ProfileContext(id: id, database: database, diagnostics: diagnostics, onError: onError)
    }

    /// The Profile's database in its folder, or one in memory when there is no folder or it cannot be opened.
    private func database(for id: ProfileID) -> ProfileDatabase {
        if let layout {
            do {
                return try ProfileDatabase(file: layout.profileDatabaseFile(for: id))
            } catch {
                onError("The Profile's database could not be opened; its Tabs will not be saved", error)
            }
        }
        // An in-memory database cannot fail to open.
        return try! ProfileDatabase.inMemory()
    }

    private func remember(_ id: ProfileID) {
        do {
            try appDatabase?.setLastActiveProfileID(id)
        } catch {
            onError("The Active profile could not be saved", error)
        }
    }

    /// Erases a deleted Profile's folder, then its data store once WebKit has released it, then forgets the Profile.
    private func erase(_ id: ProfileID) async throws {
        if let layout {
            let folder = layout.profileDirectory(for: id)
            if FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: folder)
            }
        }
        var lastError: (any Error)?
        for attempt in 0..<dataStoreRemovalAttempts {
            do {
                try await ProfileWebContext.removeDataStore(of: id)
                lastError = nil
                break
            } catch {
                // A Profile that never loaded a page may have no data store to remove.
                if !(await ProfileWebContext.dataStoreExists(for: id)) {
                    lastError = nil
                    break
                }
                lastError = error
                if attempt < dataStoreRemovalAttempts - 1 { try? await Task.sleep(for: .milliseconds(100)) }
            }
        }
        if let lastError {
            onError("The Profile's website data could not be erased yet; it will be at the next launch", lastError)
            throw lastError
        }
        try appDatabase?.delete(id)
    }

    private static func cleanName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cleanSymbol(_ symbol: String) -> String? {
        symbol.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init)
    }
}
