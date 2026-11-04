// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraStore
import SafiraWeb
import Testing

/// The Matching tab search across Profiles. The owners build real WebKit data stores; the pages are on loopback.
@MainActor
@Suite(.serialized) struct MatchingTabRegistryTests {
    @Test func aProfileNotShownSinceLaunchIsSearchedByItsSavedTabsWithoutBeingLoadedThenFocused() async throws {
        let layout = StoreLayout(root: FileManager.default.temporaryDirectory
            .appending(path: "safira-\(UUID().uuidString)", directoryHint: .isDirectory))
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let server = try await LocalServer.start(.http)
        let docs = URL(string: "http://127.0.0.1:\(server.port)/docs")!
        let first = Profile(id: ProfileID(rawValue: UUID()), name: "Home")
        let second = Profile(id: ProfileID(rawValue: UUID()), name: "Work")
        let space = SpaceRecord(id: SpaceID(), name: "Dev", emoji: "🛠", tabs: [
            TabRecord(id: TabID(), address: URL(string: "http://127.0.0.1:\(server.port)/other")),
            TabRecord(id: TabID(), address: docs),
        ])
        do {
            let app = try AppDatabase(file: layout.appDatabaseFile)
            try app.add(first)
            try app.add(second)
            try await ProfileDatabase(file: layout.profileDatabaseFile(for: second.id))
                .save(SavedSession(spaces: [space], activeSpaceID: space.id))
        }
        do {
            let registry = ProfileRegistry(layout: layout)
            _ = registry.active
            let address = try #require(NormalizedAddress(URL(string: "http://127.0.0.1:\(server.port)/docs/?utm_source=mail#intro")!))

            let match = try #require(registry.matchingTab(for: address, in: second.id))

            #expect(match == MatchingTab(profile: second.id, space: space.id, tab: space.tabs[1].id))
            #expect(registry.loadedContexts.map(\.id) == [first.id])
            #expect(registry.activeProfileID == first.id)
            #expect(registry.matchingTab(for: address, in: first.id) == nil)

            #expect(registry.focus(match, openedFrom: docs))

            #expect(registry.activeProfileID == second.id)
            #expect(registry.active.session.selectedTabID == space.tabs[1].id)
            #expect(registry.active.session.matchBanner?.link == docs)
            #expect(registry.active.session.tabs.count == 2)
            #expect(registry.matchingTab(for: address, in: second.id) == match)

            await registry.saveAll()
        }
        server.stop()
        await removeDataStoreWhenReleased(first.id)
        await removeDataStoreWhenReleased(second.id)
    }

    /// The Space rail draws every Profile's Spaces; one not shown since launch is read from its saved Spaces.
    @Test func theSpacesOfAProfileNotShownSinceLaunchAreReadWithoutLoadingItThenFollowItsSession() async throws {
        let layout = StoreLayout(root: FileManager.default.temporaryDirectory
            .appending(path: "safira-\(UUID().uuidString)", directoryHint: .isDirectory))
        defer { try? FileManager.default.removeItem(at: layout.root) }
        let first = Profile(id: ProfileID(rawValue: UUID()), name: "Home")
        let second = Profile(id: ProfileID(rawValue: UUID()), name: "Work")
        let dev = SpaceRecord(id: SpaceID(), name: "Dev", emoji: "🛠", paletteID: "teal-green")
        let ops = SpaceRecord(id: SpaceID(), name: "Ops", emoji: "🚀")
        do {
            let app = try AppDatabase(file: layout.appDatabaseFile)
            try app.add(first)
            try app.add(second)
            try await ProfileDatabase(file: layout.profileDatabaseFile(for: second.id))
                .save(SavedSession(spaces: [dev, ops], activeSpaceID: ops.id))
        }
        do {
            let registry = ProfileRegistry(layout: layout)
            _ = registry.active

            #expect(registry.spaceSummary(of: second.id) == ProfileSpaces(
                spaces: [SpaceSummary(id: dev.id, name: "Dev", emoji: "🛠", paletteID: "teal-green"),
                         SpaceSummary(id: ops.id, name: "Ops", emoji: "🚀")],
                lastSpaceID: ops.id))
            #expect(registry.loadedContexts.map(\.id) == [first.id])
            #expect(registry.spaceSummary(of: first.id).spaces.map(\.name) == ["Home"])
            #expect(registry.spaceSummary(of: ProfileID(rawValue: UUID())) == ProfileSpaces())

            registry.selectProfile(second.id)
            registry.active.session.selectSpace(dev.id)

            #expect(registry.spaceSummary(of: second.id).lastSpaceID == dev.id)
            #expect(registry.spaceSummary(of: second.id).spaces.map(\.name) == ["Dev", "Ops"])

            await registry.saveAll()
        }
        await removeDataStoreWhenReleased(first.id)
        await removeDataStoreWhenReleased(second.id)
    }

    @Test func aMatchOfAProfileThatNoLongerExistsIsRefusedAndTheActiveProfileStays() async throws {
        let registry = ProfileRegistry(layout: nil)
        let gone = MatchingTab(profile: ProfileID(rawValue: UUID()), space: SpaceID(), tab: TabID())
        let active = registry.activeProfileID

        #expect(!registry.focus(gone, openedFrom: URL(string: "https://example.com")!))
        #expect(registry.activeProfileID == active)
        #expect(registry.matchingTab(for: NormalizedAddress(URL(string: "https://example.com")!)!, in: gone.profile) == nil)
        await removeDataStoreWhenReleased(active)
    }
}
