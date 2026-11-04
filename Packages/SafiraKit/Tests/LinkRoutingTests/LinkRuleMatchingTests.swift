// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Testing

// The cases of the reference picker's resolve mode, with the same inputs and the same answers.

private func matches(_ rule: LinkRule, _ address: String, from opener: String? = nil) -> Bool {
    rule.matches(URL(string: address)!, openerBundleIdentifier: opener)
}

@Suite struct LinkRuleHostMatchingTests {
    @Test func aHostRuleMatchesThatHost() {
        let rule = LinkRule(host: "github.com", profile: "Work")
        #expect(matches(rule, "https://github.com/anything"))
        #expect(matches(rule, "http://github.com"))
    }

    @Test func aHostRuleMatchesItsSubdomains() {
        let rule = LinkRule(host: "github.com", profile: "Work")
        #expect(matches(rule, "https://gist.github.com/x"))
        #expect(matches(rule, "https://a.b.github.com/"))
    }

    @Test func aHostRuleDoesNotMatchAHostThatMerelyEndsWithIt() {
        let rule = LinkRule(host: "github.com", profile: "Work")
        #expect(!matches(rule, "https://notgithub.com/"))
        #expect(!matches(rule, "https://github.com.evil.example/"))
        #expect(!matches(rule, "https://example.com/github.com"))
    }

    @Test func aSubdomainRuleDoesNotMatchTheParentHost() {
        #expect(!matches(LinkRule(host: "gist.github.com", profile: "Work"), "https://github.com/"))
    }

    @Test func hostsAreComparedWithoutLetterCase() {
        #expect(matches(LinkRule(host: "GitHub.com", profile: "Work"), "https://GIST.github.COM/x"))
    }

    @Test func aHostRuleNeverMatchesALocalFile() {
        #expect(!LinkRule(host: "github.com", profile: "Work").matches(URL(filePath: "/tmp/github.com"), openerBundleIdentifier: nil))
    }
}

@Suite struct LinkRulePathMatchingTests {
    private let rule = LinkRule(host: "github.com", path: "/Example-Org", profile: "Work")

    @Test func aPathMatchesALeadingRunOfWholeSegments() {
        #expect(matches(rule, "https://github.com/example-org"))
        #expect(matches(rule, "https://github.com/example-org/"))
        #expect(matches(rule, "https://github.com/example-org/repo/pull/1"))
    }

    @Test func aPathIsComparedWithoutLetterCase() {
        #expect(matches(rule, "https://github.com/EXAMPLE-ORG/Repo"))
    }

    @Test func aPathDoesNotMatchAPartialSegment() {
        #expect(!matches(rule, "https://github.com/example-orgx"))
        #expect(!matches(rule, "https://github.com/example-org-two/repo"))
    }

    @Test func aPathDoesNotMatchLaterSegments() {
        #expect(!matches(rule, "https://github.com/other/example-org"))
    }

    @Test func aMultiSegmentPathMatchesOnlyAllOfItsSegments() {
        let deep = LinkRule(host: "github.com", path: "/example-org/repo", profile: "Work")
        #expect(matches(deep, "https://github.com/example-org/repo/issues"))
        #expect(!matches(deep, "https://github.com/example-org/other"))
        #expect(!matches(deep, "https://github.com/example-org"))
    }

    @Test func aTrailingSlashOrAMissingLeadingSlashInTheRuleChangesNothing() {
        #expect(matches(LinkRule(host: "github.com", path: "/example-org/", profile: "Work"), "https://github.com/example-org/repo"))
        #expect(matches(LinkRule(host: "github.com", path: "example-org", profile: "Work"), "https://github.com/example-org/repo"))
    }

    @Test func aRootPathMatchesEveryPath() {
        let root = LinkRule(host: "github.com", path: "/", profile: "Work")
        #expect(matches(root, "https://github.com"))
        #expect(matches(root, "https://github.com/anything/at/all"))
    }

    @Test func theQueryAndTheFragmentAreNotPartOfThePath() {
        #expect(matches(rule, "https://github.com/example-org?tab=repositories#readme"))
        #expect(!matches(LinkRule(host: "github.com", path: "/tab", profile: "Work"), "https://github.com/?x=/tab"))
    }

    @Test func aPercentEncodedPathIsComparedDecoded() {
        #expect(matches(LinkRule(host: "example.com", path: "/my docs", profile: "Work"), "https://example.com/my%20docs/page"))
    }
}

@Suite struct LinkRuleOpenerMatchingTests {
    @Test func anOpenerRuleMatchesThatAppOnly() {
        let rule = LinkRule(opener: "com.tinyspeck.slackmacgap", profile: "Work")
        #expect(matches(rule, "https://example.com/", from: "com.tinyspeck.slackmacgap"))
        #expect(!matches(rule, "https://example.com/", from: "com.apple.mail"))
    }

    @Test func anOpenerRuleDoesNotMatchALinkWithNoKnownOpener() {
        #expect(!matches(LinkRule(opener: "com.tinyspeck.slackmacgap", profile: "Work"), "https://example.com/"))
    }

    @Test func everyFieldTheRuleSetsMustMatch() {
        let rule = LinkRule(host: "github.com", path: "/example-org", opener: "com.tinyspeck.slackmacgap", profile: "Work")
        #expect(matches(rule, "https://github.com/example-org/repo", from: "com.tinyspeck.slackmacgap"))
        #expect(!matches(rule, "https://github.com/example-org/repo", from: "com.apple.mail"))
        #expect(!matches(rule, "https://gitlab.com/example-org/repo", from: "com.tinyspeck.slackmacgap"))
        #expect(!matches(rule, "https://github.com/other", from: "com.tinyspeck.slackmacgap"))
    }
}

@Suite struct LinkRuleIgnoredTests {
    @Test func aRuleWithNeitherAHostNorAnOpenerMatchesNothing() {
        #expect(!matches(LinkRule(profile: "Work"), "https://example.com/"))
        #expect(!matches(LinkRule(path: "/example-org", profile: "Work"), "https://github.com/example-org"))
    }

    @Test func blankFieldsCountAsAbsent() {
        let rule = LinkRule(host: "  ", path: "", opener: "", profile: "Work")
        #expect(!rule.isActive)
        #expect(!matches(rule, "https://example.com/"))
    }
}
