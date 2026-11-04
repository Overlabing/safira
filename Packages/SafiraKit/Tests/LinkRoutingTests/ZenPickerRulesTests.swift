// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Testing

private let sample = """
[
  {"host": "alpha.example", "path": "/team", "target": "first"},
  {"opener": "com.example.chat", "target": "second"},
  {"host": "beta.example", "target": "first"},
  {"host": "gamma.example", "target": "third"},
  {"target": "first"}
]
"""

@Suite struct ZenPickerRulesTests {
    @Test func theTargetsAreListedOnceInTheOrderTheyAppear() throws {
        let zen = try ZenPickerRules.parse(Data(sample.utf8)).get()
        #expect(zen.targets == ["first", "second", "third"])
    }

    @Test func eachMappedTargetBecomesTheProfileTheUserPicked() throws {
        let zen = try ZenPickerRules.parse(Data(sample.utf8)).get()

        let (rules, skipped) = zen.linkRules(profileReference: ["first": "profile-a", "second": "profile-b"])

        #expect(rules == [
            LinkRule(host: "alpha.example", path: "/team", profile: "profile-a"),
            LinkRule(opener: "com.example.chat", profile: "profile-b"),
            LinkRule(host: "beta.example", profile: "profile-a"),
        ])
        // The "third" target was not mapped, and the last rule has neither a host nor an Opener.
        #expect(skipped == 2)
    }

    @Test(arguments: [
        ("not json", ZenPickerImportError.notJSON),
        (#"{"version": 1}"#, ZenPickerImportError.notAList),
        (#"["x"]"#, ZenPickerImportError.invalidRule(index: 0)),
        (#"[{"host": "a.example", "target": "t"}, {"host": 3, "target": "t"}]"#, ZenPickerImportError.invalidRule(index: 1)),
    ])
    func aFileThatIsNotAZenPickerListIsRefused(json: String, expected: ZenPickerImportError) {
        #expect(ZenPickerRules.parse(Data(json.utf8)) == .failure(expected))
    }
}
