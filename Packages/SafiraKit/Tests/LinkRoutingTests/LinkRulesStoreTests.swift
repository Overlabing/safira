// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Testing

func temporaryRulesFile() throws -> URL {
    let folder = FileManager.default.temporaryDirectory.appending(path: "safira-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder.appending(path: "link-rules.json")
}

private func rules(in store: LinkRulesStore) -> [LinkRule] {
    guard case .rules(let set) = store.load() else { return [] }
    return set.rules
}

private let handWritten = """
{
  "version": 1,
  "rules": [
    {"host": "alpha.example", "profile": "Work", "note": "kept by hand"},
    {"host": "beta.example", "path": "/team", "profile": "Home", "space": "Reading", "newTab": true}
  ],
  "nativeApps": {"slack": false},
  "comment": "the user's own key"
}
"""

@Suite struct LinkRulesStoreTests {
    @Test func appendingToAMissingFileCreatesItWithTheRule() throws {
        let url = try temporaryRulesFile()
        let store = LinkRulesStore(url: url)

        try store.append(LinkRule(host: "example.com", profile: "Work"))

        #expect(rules(in: store) == [LinkRule(host: "example.com", profile: "Work")])
        #expect(LinkRulesFile(url: url).load() == .rules(LinkRuleSet(rules: [LinkRule(host: "example.com", profile: "Work")])))
    }

    @Test func appendingAddsAtTheBottomAndKeepsEverythingTheUserWrote() throws {
        let url = try temporaryRulesFile()
        try Data(handWritten.utf8).write(to: url)
        let store = LinkRulesStore(url: url)

        try store.append(LinkRule(host: "gamma.example", profile: "Work", space: "Dev"))

        #expect(rules(in: store).map(\.host) == ["alpha.example", "beta.example", "gamma.example"])
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(saved["comment"] as? String == "the user's own key")
        #expect((saved["nativeApps"] as? [String: Bool]) == ["slack": false])
        let first = try #require((saved["rules"] as? [[String: Any]])?.first)
        #expect(first["note"] as? String == "kept by hand")
        guard case .rules(let set) = store.load() else { Issue.record("not valid"); return }
        #expect(set.enabledNativeApps == Set(NativeApp.allCases).subtracting([.slack]))
        #expect(set.rules[1] == LinkRule(host: "beta.example", path: "/team", profile: "Home", space: "Reading", forcesNewTab: true))
    }

    @Test(arguments: [
        "{ broken", #"{"version": 2, "rules": []}"#, #"{"version": 1, "rules": [{"host": "a.example"}]}"#, "",
    ])
    func anInvalidExistingFileIsNeverOverwritten(content: String) throws {
        let url = try temporaryRulesFile()
        try Data(content.utf8).write(to: url)
        let store = LinkRulesStore(url: url)
        let valid = Data(handWritten.utf8)

        #expect(throws: LinkRulesEditError.self) { try store.append(LinkRule(host: "x.example", profile: "Work")) }
        #expect(throws: LinkRulesEditError.self) { try store.remove(at: 0) }
        #expect(throws: LinkRulesEditError.self) { try store.move(from: 0, to: 1) }
        #expect(throws: LinkRulesEditError.self) { try store.importFile(valid, mode: .replace) }
        #expect(throws: LinkRulesEditError.self) { try store.importFile(valid, mode: .addToEnd) }
        #expect(throws: LinkRulesEditError.self) { try store.exportData() }

        #expect(try Data(contentsOf: url) == Data(content.utf8))
    }

    @Test func aFileThatIsADirectoryIsNotOverwrittenEither() throws {
        let url = try temporaryRulesFile()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        #expect(throws: LinkRulesEditError.existingFileInvalid(.unreadable)) {
            try LinkRulesStore(url: url).append(LinkRule(host: "x.example", profile: "Work"))
        }
    }

    @Test func removingAndMovingChangeTheOrderAndNothingElse() throws {
        let url = try temporaryRulesFile()
        try Data(handWritten.utf8).write(to: url)
        let store = LinkRulesStore(url: url)

        try store.move(from: 0, to: 1)
        #expect(rules(in: store).map(\.host) == ["beta.example", "alpha.example"])

        try store.remove(at: 0)
        #expect(rules(in: store).map(\.host) == ["alpha.example"])
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(saved["comment"] as? String == "the user's own key")
        #expect(((saved["rules"] as? [[String: Any]])?.first)?["note"] as? String == "kept by hand")
    }

    @Test func aRuleThatDoesNotExistIsRefusedAndTheFileIsUntouched() throws {
        let url = try temporaryRulesFile()
        try Data(handWritten.utf8).write(to: url)
        let before = try Data(contentsOf: url)
        let store = LinkRulesStore(url: url)

        #expect(throws: LinkRulesEditError.noSuchRule) { try store.remove(at: 2) }
        #expect(throws: LinkRulesEditError.noSuchRule) { try store.remove(at: -1) }
        #expect(throws: LinkRulesEditError.noSuchRule) { try store.move(from: 0, to: 5) }

        #expect(try Data(contentsOf: url) == before)
    }

    @Test func exportedRulesImportBackAsTheSameRules() throws {
        let source = LinkRulesStore(url: try temporaryRulesFile())
        try Data(handWritten.utf8).write(to: source.url)
        try source.append(LinkRule(opener: "com.example.mail", profile: "Home"))
        let exported = try source.exportData()

        let target = LinkRulesStore(url: try temporaryRulesFile())
        try target.importFile(exported, mode: .replace)

        #expect(target.load() == source.load())
        #expect(rules(in: target).count == 3)
    }

    @Test func exportingWithNoFileGivesAnEmptyValidList() throws {
        let store = LinkRulesStore(url: try temporaryRulesFile())
        #expect(LinkRuleSet.parse(try store.exportData()) == .success(LinkRuleSet()))
    }

    @Test func importingToTheEndKeepsTheExistingRulesFirst() throws {
        let url = try temporaryRulesFile()
        try Data(handWritten.utf8).write(to: url)
        let store = LinkRulesStore(url: url)

        try store.importFile(Data(#"{"version":1,"rules":[{"host":"imported.example","profile":"Work"}]}"#.utf8), mode: .addToEnd)

        #expect(rules(in: store).map(\.host) == ["alpha.example", "beta.example", "imported.example"])
        let saved = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(saved["comment"] as? String == "the user's own key")
    }

    @Test func importingToReplaceTakesTheImportedFile() throws {
        let url = try temporaryRulesFile()
        try Data(handWritten.utf8).write(to: url)
        let store = LinkRulesStore(url: url)

        try store.importFile(Data(#"{"version":1,"rules":[{"host":"imported.example","profile":"Work"}]}"#.utf8), mode: .replace)

        #expect(rules(in: store).map(\.host) == ["imported.example"])
    }

    @Test(arguments: [LinkRulesImportMode.addToEnd, .replace])
    func anInvalidImportIsRefusedAndTheExistingRulesStayByteForByte(mode: LinkRulesImportMode) throws {
        let url = try temporaryRulesFile()
        try Data(handWritten.utf8).write(to: url)
        let store = LinkRulesStore(url: url)

        #expect(throws: LinkRulesEditError.importInvalid(.notJSON)) { try store.importFile(Data("nope".utf8), mode: mode) }
        #expect(throws: LinkRulesEditError.importInvalid(.invalidField(location: "rules[0].profile"))) {
            try store.importFile(Data(#"{"version":1,"rules":[{"host":"a.example"}]}"#.utf8), mode: mode)
        }
        #expect(throws: LinkRulesEditError.importInvalid(.unsupportedVersion)) {
            try store.importFile(Data(#"{"version":9,"rules":[]}"#.utf8), mode: mode)
        }

        #expect(try Data(contentsOf: url) == Data(handWritten.utf8))
    }

    @Test func aRuleAddedAfterAHandEditLandsInTheHandEditedFile() throws {
        let url = try temporaryRulesFile()
        try Data(handWritten.utf8).write(to: url)
        let store = LinkRulesStore(url: url)
        try store.append(LinkRule(host: "first.example", profile: "Work"))
        try Data(#"{"version":1,"rules":[{"host":"hand.example","profile":"Work"}]}"#.utf8).write(to: url)

        try store.append(LinkRule(host: "second.example", profile: "Work"))

        #expect(rules(in: store).map(\.host) == ["hand.example", "second.example"])
    }
}
