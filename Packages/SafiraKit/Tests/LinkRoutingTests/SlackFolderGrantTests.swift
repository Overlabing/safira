// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Preferences
import Testing

/// A fixture folder shaped like Slack's own, never Slack's real data.
private func fixtureFolder(workspaces: String = #"{"T0ACME1": {"domain": "acme", "name": "Acme"}, "T0OTHER2": {"domain": "Other"}}"#) throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "safira-slack-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder.appending(path: "storage"), withIntermediateDirectories: true)
    try Data(#"{"workspaces": \#(workspaces), "unrelated": [1, 2]}"#.utf8).write(to: folder.appending(path: "storage/root-state.json"))
    return folder
}

private func freshDefaults() -> InMemoryKeyValueStore {
    InMemoryKeyValueStore()
}

@Suite struct SlackFolderGrantTests {
    @Test func withoutAGrantNothingIsKnownAndNothingFails() {
        let grant = SlackFolderGrant(store: freshDefaults())
        #expect(!grant.isGranted)
        #expect(grant.teamID(forDomain: "acme") == nil)
    }

    @Test func aGrantedFolderGivesTheTeamIdentifierOfAWorkspaceDomain() throws {
        let grant = SlackFolderGrant(store: freshDefaults())
        try grant.grant(try fixtureFolder())

        #expect(grant.isGranted)
        #expect(grant.teamID(forDomain: "acme") == "T0ACME1")
        #expect(grant.teamID(forDomain: "other") == "T0OTHER2")
        #expect(grant.teamID(forDomain: "missing") == nil)
    }

    @Test func theGrantIsKeptAcrossInstances() throws {
        let defaults = freshDefaults()
        try SlackFolderGrant(store: defaults).grant(try fixtureFolder())
        #expect(SlackFolderGrant(store: defaults).teamID(forDomain: "acme") == "T0ACME1")
    }

    @Test func revokingTheGrantForgetsTheFolder() throws {
        let grant = SlackFolderGrant(store: freshDefaults())
        try grant.grant(try fixtureFolder())

        grant.revoke()

        #expect(!grant.isGranted)
        #expect(grant.teamID(forDomain: "acme") == nil)
    }

    @Test func aFolderThatIsNotSlacksIsRefusedAndKeepsNothing() throws {
        let grant = SlackFolderGrant(store: freshDefaults())
        let empty = FileManager.default.temporaryDirectory.appending(path: "safira-empty-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        #expect(throws: SlackFolderError.notSlackFolder) { try grant.grant(empty) }
        #expect(!grant.isGranted)
    }

    @Test func aGrantedFolderThatLaterDisappearsGivesNothingWithoutAnError() throws {
        let grant = SlackFolderGrant(store: freshDefaults())
        let folder = try fixtureFolder()
        try grant.grant(folder)
        try FileManager.default.removeItem(at: folder)

        #expect(grant.teamID(forDomain: "acme") == nil)
    }

    @Test func aStateFileThatIsNotWhatSlackWritesGivesNothing() {
        #expect(SlackFolderGrant.teamID(forDomain: "acme", inWorkspaceState: Data("nonsense".utf8)) == nil)
        #expect(SlackFolderGrant.teamID(forDomain: "acme", inWorkspaceState: Data(#"{"workspaces": []}"#.utf8)) == nil)
    }
}
