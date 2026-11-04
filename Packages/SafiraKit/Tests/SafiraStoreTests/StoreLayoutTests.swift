// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraStore
import Testing

@Test func eachProfileHasItsOwnFolderNamedByItsUUID() throws {
    let layout = StoreLayout(root: URL(filePath: "/tmp/safira-support/", directoryHint: .isDirectory))
    let profile = try #require(ProfileID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))

    #expect(layout.profileDirectory(for: profile).path(percentEncoded: false)
        == "/tmp/safira-support/Profiles/6F9619FF-8B86-D011-B42D-00C04FC964FF/")
}

@Test func debugModeLogsLiveInALogsFolderOfTheAppSupportRoot() {
    let layout = StoreLayout(root: URL(filePath: "/tmp/safira-support/", directoryHint: .isDirectory))

    #expect(layout.logsDirectory.path(percentEncoded: false) == "/tmp/safira-support/Logs/")
}

@Test func eachProfileDatabaseLivesInItsProfileFolder() throws {
    let layout = StoreLayout(root: URL(filePath: "/tmp/safira-support/", directoryHint: .isDirectory))
    let profile = try #require(ProfileID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))

    #expect(layout.profileDatabaseFile(for: profile).path(percentEncoded: false)
        == "/tmp/safira-support/Profiles/6F9619FF-8B86-D011-B42D-00C04FC964FF/profile.sqlite")
    #expect(layout.appDatabaseFile.path(percentEncoded: false) == "/tmp/safira-support/app.sqlite")
}

@Test func theLinkPickerChoiceLogLivesInTheAppSupportRoot() {
    let layout = StoreLayout(root: URL(filePath: "/tmp/safira-support/", directoryHint: .isDirectory))

    #expect(layout.linkChoiceLogFile.path(percentEncoded: false) == "/tmp/safira-support/link-choices.jsonl")
    #expect(layout.linkRulesFile.path(percentEncoded: false) == "/tmp/safira-support/link-rules.json")
}
