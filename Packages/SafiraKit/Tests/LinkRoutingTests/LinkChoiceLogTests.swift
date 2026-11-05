// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Preferences
import SafiraCore
import Testing

private let profile = ProfileID(uuidString: "11111111-1111-4111-8111-111111111111")!

@MainActor
private func logFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)/link-choices.jsonl")
}

@Test func theChoiceLogIsOffByDefault() {
    #expect(LinkChoiceLogSettings().isEnabled == false)
    #expect(LinkChoiceLogSettings.defaultEntries == [
        DefaultEntry(
            id: "linkPicker.choiceLog",
            title: "Log Link picker choices",
            value: "Off",
            explanation: "Writes the host of each link you send to a Profile, and the Profile, to a file on this Mac, "
                + "never the path or anything after it. The file stays on this Mac; Safira never sends it anywhere.",
            whereToChange: "Safira menu",
            control: .toggle(isOn: false)
        ),
    ])
}

@Test func theChoiceLogSettingIsKeptAcrossLaunchesAndIsOffInAnEmptyStore() {
    let values = InMemoryKeyValueStore()
    let store = LinkChoiceLogSettingsStore(store: values)

    #expect(store.load(unreadable: { _ in }).isEnabled == false)
    store.save(LinkChoiceLogSettings(isEnabled: true))
    #expect(LinkChoiceLogSettingsStore(store: values).load(unreadable: { _ in }).isEnabled == true)
}

@Test func theChoiceLogTheOldStoreTurnedOnStaysOnAfterTheMigration() throws {
    let domain = "safira-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set(true, forKey: "linkPicker.choiceLog")

    LegacyPreference.migrate([LinkChoiceLogSettingsStore.legacy], in: defaults, domain: domain)

    #expect(LinkChoiceLogSettingsStore(store: defaults).load(unreadable: { _ in }).isEnabled)
}

@MainActor
@Test func aLogLineHoldsTheLowercasedHostAndTheProfileNeverThePathQueryFragmentPortOrCredentials() throws {
    let file = logFile()
    let log = LinkChoiceLog(file: file, isEnabled: true)

    log.record(try #require(URL(string: "https://user:pass@Docs.Example.com:8443/private/path?token=abc#section")), chosen: profile)
    log.record(try #require(URL(string: "http://swift.org/")), chosen: profile)

    let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n")
    #expect(lines == [
        "{\"host\":\"docs.example.com\",\"profile\":\"11111111-1111-4111-8111-111111111111\"}",
        "{\"host\":\"swift.org\",\"profile\":\"11111111-1111-4111-8111-111111111111\"}",
    ])
}

@MainActor
@Test func aLogThatIsOffWritesNothingAndOneTurnedOnStartsWritingFromThatPoint() throws {
    let file = logFile()
    let log = LinkChoiceLog(file: file, isEnabled: false)
    let url = try #require(URL(string: "https://example.com/a"))

    log.record(url, chosen: profile)
    #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))

    log.isEnabled = true
    log.record(url, chosen: profile)
    #expect(try String(contentsOf: file, encoding: .utf8).split(separator: "\n").count == 1)
}

@MainActor
@Test func aLocalFileHasNoHostAndIsNotLogged() {
    let file = logFile()
    let log = LinkChoiceLog(file: file, isEnabled: true)

    log.record(URL(filePath: "/Users/someone/page.html"), chosen: profile)

    #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
}

@MainActor
@Test func aLogThatCannotBeWrittenReportsTheErrorInsteadOfCrashing() throws {
    // The file's folder is a regular file, so it cannot be created.
    let blocker = FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)")
    try Data().write(to: blocker)
    var reported = 0
    let log = LinkChoiceLog(file: blocker.appending(path: "link-choices.jsonl"), isEnabled: true) { _ in reported += 1 }

    log.record(try #require(URL(string: "https://example.com/")), chosen: profile)

    #expect(reported == 1)
}
