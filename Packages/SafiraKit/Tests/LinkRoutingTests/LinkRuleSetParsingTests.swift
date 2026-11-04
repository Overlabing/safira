// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Testing

private func parse(_ json: String) -> Result<LinkRuleSet, LinkRulesError> {
    LinkRuleSet.parse(Data(json.utf8))
}

@Suite struct LinkRuleSetParsingTests {
    @Test func theDocumentedExampleParses() throws {
        let json = """
        {
          "version": 1,
          "rules": [
            {"host": "github.com", "path": "/example-org", "profile": "Pro", "space": "Dev"},
            {"host": "meet.google.com", "profile": "Pro", "newTab": true},
            {"opener": "com.tinyspeck.slackmacgap", "profile": "Pro"}
          ],
          "nativeApps": {"slack": true, "linear": true, "notion": false, "figma": true}
        }
        """
        let set = try parse(json).get()

        #expect(set.rules == [
            LinkRule(host: "github.com", path: "/example-org", profile: "Pro", space: "Dev"),
            LinkRule(host: "meet.google.com", profile: "Pro", forcesNewTab: true),
            LinkRule(opener: "com.tinyspeck.slackmacgap", profile: "Pro"),
        ])
        #expect(set.enabledNativeApps == [.slack, .linear, .figma])
    }

    @Test func nativeAppsAreAllOnWhenTheFileSaysNothingAboutThem() throws {
        #expect(try parse(#"{"version": 1, "rules": []}"#).get().enabledNativeApps == [.slack, .linear, .notion, .figma])
    }

    @Test func aRuleKeepsItsFileOrder() throws {
        let set = try parse(#"{"version":1,"rules":[{"host":"b.com","profile":"P"},{"host":"a.com","profile":"P"}]}"#).get()
        #expect(set.rules.map(\.host) == ["b.com", "a.com"])
    }

    @Test func unknownKeysAreIgnored() throws {
        let set = try parse(#"{"version":1,"comment":"x","rules":[{"host":"a.com","profile":"P","note":1}],"nativeApps":{"mail":false}}"#).get()
        #expect(set.rules.count == 1)
        #expect(set.enabledNativeApps.count == 4)
    }

    @Test(arguments: [
        ("not json at all", LinkRulesError.notJSON),
        ("", LinkRulesError.notJSON),
        ("[]", LinkRulesError.notJSON),
        (#"{"rules": []}"#, LinkRulesError.unsupportedVersion),
        (#"{"version": 2, "rules": []}"#, LinkRulesError.unsupportedVersion),
        (#"{"version": "1", "rules": []}"#, LinkRulesError.unsupportedVersion),
        (#"{"version": 1}"#, LinkRulesError.invalidField(location: "rules")),
        (#"{"version": 1, "rules": {}}"#, LinkRulesError.invalidField(location: "rules")),
        (#"{"version": 1, "rules": ["x"]}"#, LinkRulesError.invalidField(location: "rules[0]")),
        (#"{"version": 1, "rules": [{"host": "a.com"}]}"#, LinkRulesError.invalidField(location: "rules[0].profile")),
        (#"{"version": 1, "rules": [{"host": "a.com", "profile": ""}]}"#, LinkRulesError.invalidField(location: "rules[0].profile")),
        (#"{"version": 1, "rules": [{"host": "a.com", "profile": "P"}, {"host": 4, "profile": "P"}]}"#,
         LinkRulesError.invalidField(location: "rules[1].host")),
        (#"{"version": 1, "rules": [{"host": "a.com", "profile": "P", "newTab": "yes"}]}"#,
         LinkRulesError.invalidField(location: "rules[0].newTab")),
        (#"{"version": 1, "rules": [], "nativeApps": []}"#, LinkRulesError.invalidField(location: "nativeApps")),
        (#"{"version": 1, "rules": [], "nativeApps": {"slack": "no"}}"#, LinkRulesError.invalidField(location: "nativeApps.slack")),
    ])
    func anInvalidFileIsRefusedWithTheReasonAndTheLocation(json: String, expected: LinkRulesError) {
        #expect(parse(json) == .failure(expected))
    }

    @Test func theErrorNeverQuotesAValueFromTheFile() {
        let result = parse(#"{"version": 1, "rules": [{"host": "secret-host.example", "profile": 7}]}"#)
        guard case .failure(let error) = result else {
            Issue.record("expected a failure")
            return
        }
        #expect(!error.explanation.contains("secret-host"))
        #expect(error.explanation == "\"rules[0].profile\" is missing or has the wrong type.")
    }
}

@Suite struct LinkRulesFileTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "safira-rules-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aMissingFileMeansNoRules() throws {
        let file = LinkRulesFile(url: try folder().appending(path: "link-rules.json"))
        #expect(file.load() == .rules(.empty))
    }

    @Test func aValidFileIsRead() throws {
        let url = try folder().appending(path: "link-rules.json")
        try Data(#"{"version":1,"rules":[{"host":"a.com","profile":"P"}]}"#.utf8).write(to: url)
        #expect(LinkRulesFile(url: url).load() == .rules(LinkRuleSet(rules: [LinkRule(host: "a.com", profile: "P")])))
    }

    @Test func anInvalidFileIsReportedAsInvalid() throws {
        let url = try folder().appending(path: "link-rules.json")
        try Data("{ broken".utf8).write(to: url)
        #expect(LinkRulesFile(url: url).load() == .invalid(.notJSON))
    }

    @Test func theFileIsReadAgainForEachLink() throws {
        let url = try folder().appending(path: "link-rules.json")
        let file = LinkRulesFile(url: url)
        try Data(#"{"version":1,"rules":[]}"#.utf8).write(to: url)
        #expect(file.load() == .rules(LinkRuleSet()))
        try Data(#"{"version":1,"rules":[{"opener":"x.y","profile":"P"}]}"#.utf8).write(to: url)
        #expect(file.load() == .rules(LinkRuleSet(rules: [LinkRule(opener: "x.y", profile: "P")])))
    }

    @Test func aFileThatCannotBeReadIsReportedNotTreatedAsMissing() throws {
        let directory = try folder()
        #expect(LinkRulesFile(url: directory).load() == .invalid(.unreadable))
    }
}
