// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraStore
import Testing

/// The app-level list of installed extensions in `app.sqlite`.
@Suite struct InstalledExtensionTests {
    private let file = FileManager.default.temporaryDirectory
        .appending(path: "safira-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: "app.sqlite", directoryHint: .notDirectory)
    private let work = ProfileID(rawValue: UUID(uuidString: "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A")!)
    private let personal = ProfileID(rawValue: UUID(uuidString: "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F")!)

    private func folderInstall() -> InstalledExtension {
        InstalledExtension(id: "pfikphmpnbnmihdgfbljkjgfnamcpjme", source: .folder(bookmark: Data([1, 2, 3])),
                           displayName: "Safira fixture", version: "1.2.3",
                           grantedPermissions: ["storage", "alarms"], grantedMatchPatterns: ["https://*/*"],
                           installedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    private func archiveInstall() -> InstalledExtension {
        InstalledExtension(id: "aaabacadaeafagahaiajakalamanaoap", source: .archive(fileName: "aaabacadaeafagahaiajakalamanaoap.zip"),
                           displayName: "Packed", version: "2.0", grantedPermissions: [], grantedMatchPatterns: [],
                           installedAt: Date(timeIntervalSince1970: 1_800_000_100))
    }

    @Test func theListComesBackAfterAReopenWithItsSourcesAndGrants() throws {
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let database = try AppDatabase(file: file)
        try database.save(folderInstall())
        try database.save(archiveInstall())

        let reopened = try AppDatabase(file: file).installedExtensions()

        #expect(reopened == [folderInstall(), archiveInstall()])
        #expect(reopened[0].grantedPermissions == ["alarms", "storage"])
        #expect(reopened[0].source == .folder(bookmark: Data([1, 2, 3])))
        #expect(reopened[1].source == .archive(fileName: "aaabacadaeafagahaiajakalamanaoap.zip"))
    }

    @Test func everyProfileStartsOnAndASwitchTurnedOffStaysOff() throws {
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let database = try AppDatabase(file: file)
        var installed = folderInstall()
        try database.save(installed)
        #expect(try database.installedExtensions()[0].isEnabled(in: work))
        #expect(try database.installedExtensions()[0].isEnabled(in: personal))

        installed.disabledProfiles = [personal]
        try database.save(installed)

        let reopened = try AppDatabase(file: file).installedExtensions()[0]
        #expect(reopened.isEnabled(in: work))
        #expect(!reopened.isEnabled(in: personal))
        #expect(reopened.disabledProfiles == [personal])
        // A Profile created after the install starts with it on.
        #expect(reopened.isEnabled(in: ProfileID(rawValue: UUID())))
    }

    /// Saving again keeps the identifier and the install date: an update changes the version, never the id.
    @Test func savingAgainUpdatesTheVersionUnderTheSameIdentifier() throws {
        let database = try AppDatabase.inMemory()
        var installed = folderInstall()
        try database.save(installed)
        installed.version = "1.2.4"
        installed.source = .folder(bookmark: Data([9]))
        try database.save(installed)

        let saved = try database.installedExtensions()
        #expect(saved.map(\.id) == ["pfikphmpnbnmihdgfbljkjgfnamcpjme"])
        #expect(saved[0].version == "1.2.4")
        #expect(saved[0].source == .folder(bookmark: Data([9])))
        #expect(saved[0].installedAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func aRemovedExtensionIsForgottenWithItsSwitches() throws {
        let database = try AppDatabase.inMemory()
        var installed = folderInstall()
        installed.disabledProfiles = [work]
        try database.save(installed)
        try database.save(archiveInstall())

        try database.deleteInstalledExtension(installed.id)

        #expect(try database.installedExtensions().map(\.id) == ["aaabacadaeafagahaiajakalamanaoap"])
        try database.save(folderInstall())
        #expect(try database.installedExtensions().first?.disabledProfiles == [])
    }

    @Test func aDeletedProfileLeavesNoSwitchBehind() throws {
        let database = try AppDatabase.inMemory()
        try database.add(Profile(id: work, name: "Work"))
        try database.add(Profile(id: personal, name: "Personal"))
        var installed = folderInstall()
        installed.disabledProfiles = [work, personal]
        try database.save(installed)

        try database.markForDeletion(personal)
        try database.delete(personal)

        #expect(try database.installedExtensions()[0].disabledProfiles == [work])
    }
}
