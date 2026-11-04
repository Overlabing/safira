// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import Testing

private let everyApp: Set<NativeApp> = Set(NativeApp.allCases)

private func rewrite(_ address: String, installed: Set<NativeApp> = everyApp, enabled: Set<NativeApp> = everyApp,
                     teams: [String: String] = ["acme": "T0ACME1"]) -> String? {
    let links = NativeAppLinks(applications: StubApplications(installed: installed), slack: StubSlack(teams: teams))
    return links.link(for: URL(string: address)!, enabled: enabled)?.url.absoluteString
}

@Suite struct NativeAppLinksTests {
    @Test(arguments: [
        ("https://linear.app/acme/issue/ABC-12/fix-the-thing", "linear://acme/issue/ABC-12/fix-the-thing"),
        ("https://linear.app/acme/project/roadmap-1a2b?view=board#top", "linear://acme/project/roadmap-1a2b?view=board#top"),
        ("https://www.notion.so/acme/Plan-0123456789abcdef", "notion://www.notion.so/acme/Plan-0123456789abcdef"),
        ("https://notion.so/Plan-0123456789abcdef?pvs=4", "notion://www.notion.so/Plan-0123456789abcdef?pvs=4"),
        ("https://app.notion.com/p/0123456789abcdef", "notion://app.notion.com/p/0123456789abcdef"),
        ("https://www.figma.com/design/AbC123/Landing?node-id=1-2", "figma://design/AbC123/Landing?node-id=1-2"),
        ("https://figma.com/file/AbC123/Old-file", "figma://file/AbC123/Old-file"),
        ("https://www.figma.com/board/AbC123/Workshop", "figma://board/AbC123/Workshop"),
        ("http://linear.app/acme/issue/ABC-12", "linear://acme/issue/ABC-12"),
    ])
    func aLinkOfAnInstalledAppIsRewrittenToTheAppsOwnScheme(address: String, expected: String) {
        #expect(rewrite(address) == expected)
    }

    @Test(arguments: [
        "https://linear.app/login",
        "https://linear.app/signup",
        "https://linear.app/oauth/authorize?client_id=1",
        "https://linear.app/api/graphql",
        "https://linear.app/join/abc",
        "https://linear.app/",
        "https://www.notion.so/",
        "https://www.notion.so/login",
        "https://www.notion.so/signup",
        "https://www.notion.so/oauth2/authorize",
        "https://www.notion.so/install-integration?x=1",
        "https://www.notion.so/api/v3/loadPageChunk",
        "https://www.figma.com/",
        "https://www.figma.com/login",
        "https://www.figma.com/community/file/1",
        "https://www.figma.com/oauth?x=1",
        "https://example.com/acme/issue/ABC-12",
        "https://linear.app.evil.example/acme/issue/ABC-12",
        "ftp://linear.app/acme/issue/ABC-12",
        "mailto:someone@linear.app",
    ])
    func signInPagesOtherPagesAndOtherHostsStayInTheBrowser(address: String) {
        #expect(rewrite(address) == nil)
    }

    @Test func aLinkIsNotRewrittenWhenItsAppIsNotInstalled() {
        #expect(rewrite("https://linear.app/acme/issue/ABC-12", installed: [.slack, .notion, .figma]) == nil)
        #expect(rewrite("https://www.notion.so/acme/Plan-1", installed: []) == nil)
        #expect(rewrite("https://www.figma.com/design/AbC123/Landing", installed: [.linear]) == nil)
    }

    @Test func aLinkIsNotRewrittenWhenTheUserTurnedItsAppOff() {
        #expect(rewrite("https://linear.app/acme/issue/ABC-12", enabled: [.slack, .notion, .figma]) == nil)
        #expect(rewrite("https://www.figma.com/design/AbC123/Landing", enabled: [.slack, .linear, .notion]) == nil)
    }

    @Test func theInstalledCheckUsesTheAppsBundleIdentifier() {
        #expect(NativeApp.slack.bundleIdentifier == "com.tinyspeck.slackmacgap")
        #expect(NativeApp.linear.bundleIdentifier == "com.linear")
        #expect(NativeApp.notion.bundleIdentifier == "notion.id")
        #expect(NativeApp.figma.bundleIdentifier == "com.figma.Desktop")
    }
}

@Suite struct SlackLinksTests {
    @Test func aChannelLinkNeedsTheTeamIdentifier() {
        #expect(rewrite("https://acme.slack.com/archives/C0CHANNEL1") == "slack://channel?team=T0ACME1&id=C0CHANNEL1")
    }

    @Test func aMessageLinkKeepsTheMessageTimestamp() {
        #expect(rewrite("https://acme.slack.com/archives/C0CHANNEL1/p1712345678123456")
            == "slack://channel?team=T0ACME1&id=C0CHANNEL1&message=1712345678.123456")
    }

    @Test func aThreadReplyKeepsTheThreadTimestamp() {
        #expect(rewrite("https://acme.slack.com/archives/C0CHANNEL1/p1712345999000200?thread_ts=1712345678.123456&cid=C0CHANNEL1")
            == "slack://channel?team=T0ACME1&id=C0CHANNEL1&message=1712345999.000200&thread_ts=1712345678.123456")
    }

    @Test func aShortMessageSegmentIsNotATimestamp() {
        #expect(rewrite("https://acme.slack.com/archives/C0CHANNEL1/p123") == "slack://channel?team=T0ACME1&id=C0CHANNEL1")
    }

    @Test func theWorkspaceIsFoundWithoutLetterCase() {
        #expect(rewrite("https://ACME.slack.com/archives/C0CHANNEL1") == "slack://channel?team=T0ACME1&id=C0CHANNEL1")
    }

    @Test func aWorkspaceTheFolderDoesNotKnowStaysInTheBrowser() {
        #expect(rewrite("https://other.slack.com/archives/C0CHANNEL1") == nil)
    }

    @Test func withoutTheTeamIdentifierSlackLinksStayInTheBrowser() {
        #expect(rewrite("https://acme.slack.com/archives/C0CHANNEL1", teams: [:]) == nil)
    }

    @Test(arguments: [
        "https://acme.slack.com/",
        "https://acme.slack.com/archives",
        "https://acme.slack.com/messages/C0CHANNEL1",
        "https://slack.com/archives/C0CHANNEL1",
        "https://acme.slack.com.evil.example/archives/C0CHANNEL1",
    ])
    func otherSlackAddressesStayInTheBrowser(address: String) {
        #expect(rewrite(address) == nil)
    }

    @Test func slackNotInstalledOrTurnedOffMeansTheBrowser() {
        #expect(rewrite("https://acme.slack.com/archives/C0CHANNEL1", installed: [.linear]) == nil)
        #expect(rewrite("https://acme.slack.com/archives/C0CHANNEL1", enabled: [.linear]) == nil)
    }
}
