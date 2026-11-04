// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import Testing

private let work = ProfileID(rawValue: UUID(uuidString: "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A")!)
private let personal = ProfileID(rawValue: UUID(uuidString: "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F")!)
private let mail = ExternalApp(name: "Mail", location: URL(string: "file:///Applications/Mail.app")!)
private let slack = ExternalApp(name: "Slack", location: URL(string: "file:///Applications/Slack.app")!)
private let mailto = NonWebLink(URL(string: "mailto:team@example.test")!)!
private let slackLink = NonWebLink(URL(string: "slack://channel?team=T1")!)!
private let at = Date(timeIntervalSince1970: 1_700_000_000)

/// The apps of a Mac that has Mail and Slack, and records what is opened in them.
@MainActor
private final class FakeLauncher: ExternalAppLauncher {
    var apps: [URLScheme: ExternalApp] = [URLScheme("mailto")!: mail, URLScheme("slack")!: slack]
    private(set) var opened: [(url: URL, app: ExternalApp)] = []
    var failure: (any Error)?

    func app(toOpen url: URL) -> ExternalApp? {
        url.scheme.flatMap(URLScheme.init).flatMap { apps[$0] }
    }

    func open(_ url: URL, with app: ExternalApp) async throws {
        if let failure { throw failure }
        opened.append((url, app))
    }

    var openedAddresses: [String] { opened.map { $0.url.absoluteString } }
}

/// The user at the keyboard: answers each question with the next answer and records what was asked and refused.
@MainActor
private final class FakeUser {
    var answers: [PermissionAnswer]
    private(set) var asked: [AppLinkPrompt] = []
    private(set) var refused: [AppLinkRefusal] = []

    init(_ answers: PermissionAnswer...) { self.answers = answers }

    var handlers: (FakeLauncher) -> AppLinkHandlers {
        { launcher in
            AppLinkHandlers(
                launcher: launcher,
                prompt: { [self] prompt in
                    asked.append(prompt)
                    return answers.isEmpty ? PermissionAnswer(decision: .deny, remember: false) : answers.removeFirst()
                },
                refusal: { [self] refusal in refused.append(refusal) })
        }
    }
}

private let open = PermissionAnswer(decision: .allow, remember: false)
private let alwaysOpen = PermissionAnswer(decision: .allow, remember: true)
private let dontOpen = PermissionAnswer(decision: .deny, remember: false)
private let neverOpen = PermissionAnswer(decision: .deny, remember: true)

@MainActor
@Suite struct NonWebLinkTests {
    /// A session with one Tab on `news.example`, whose page the test drives.
    private func session(_ id: ProfileID = work, permissions: SitePermissions = SitePermissions(),
                         launcher: FakeLauncher, user: FakeUser) -> (SessionFixture, SimulatedPage) {
        let fixture = SessionFixture(id: id, permissions: permissions)
        fixture.session.appLinks.handlers = user.handlers(launcher)
        fixture.visit("https://news.example/article")
        return (fixture, fixture.selectedPage!)
    }

    @Test func aMailtoLinkAsksNamingTheAppAndOpensNothingUntilTheUserAgrees() async throws {
        let launcher = FakeLauncher()
        let user = FakeUser(open)
        let (fixture, page) = session(launcher: launcher, user: user)

        page.followNonWebLink(to: "mailto:team@example.test")
        await fixture.session.appLinks.settled()

        #expect(user.asked == [AppLinkPrompt(profileID: work, scheme: URLScheme("mailto")!, app: mail,
                                             requestedBy: "news.example")])
        #expect(launcher.openedAddresses == ["mailto:team@example.test"])
        #expect(launcher.opened.map(\.app) == [mail])
        #expect(page.state.url?.absoluteString == "https://news.example/article")
    }

    @Test func theDefaultIsToAskEveryTime() async {
        let launcher = FakeLauncher()
        let user = FakeUser(open, open, dontOpen)
        let (fixture, page) = session(launcher: launcher, user: user)

        for _ in 0..<3 {
            page.followNonWebLink(to: "slack://channel?team=T1")
            await fixture.session.appLinks.settled()
        }

        #expect(user.asked.count == 3)
        #expect(launcher.openedAddresses == ["slack://channel?team=T1", "slack://channel?team=T1"])
        #expect(fixture.session.appLinks.permissions.appLinks == [])
    }

    @Test func dontOpenOpensNothingAndTheNextLinkAsksAgain() async {
        let launcher = FakeLauncher()
        let user = FakeUser(dontOpen, open)
        let (fixture, page) = session(launcher: launcher, user: user)

        page.followNonWebLink(to: "mailto:a@example.test")
        await fixture.session.appLinks.settled()
        #expect(launcher.opened.isEmpty)

        page.followNonWebLink(to: "mailto:b@example.test")
        await fixture.session.appLinks.settled()
        #expect(user.asked.count == 2)
        #expect(launcher.openedAddresses == ["mailto:b@example.test"])
    }

    @Test func aRememberedAllowOpensTheAppWithoutAskingAgainButOnlyForThatScheme() async {
        let launcher = FakeLauncher()
        let user = FakeUser(alwaysOpen, dontOpen)
        let (fixture, page) = session(launcher: launcher, user: user)

        page.followNonWebLink(to: "mailto:a@example.test")
        await fixture.session.appLinks.settled()
        page.followNonWebLink(to: "mailto:b@example.test")
        await fixture.session.appLinks.settled()
        #expect(user.asked.map(\.scheme.rawValue) == ["mailto"])
        #expect(launcher.openedAddresses == ["mailto:a@example.test", "mailto:b@example.test"])

        page.followNonWebLink(to: "slack://channel?team=T1")
        await fixture.session.appLinks.settled()
        #expect(user.asked.map(\.scheme.rawValue) == ["mailto", "slack"])
        #expect(launcher.openedAddresses.count == 2)
    }

    @Test func aRememberedChoiceInOneProfileLeavesTheOtherProfileAsking() async {
        let launcher = FakeLauncher()
        let workUser = FakeUser(alwaysOpen)
        let personalUser = FakeUser(dontOpen)
        let (inWork, workPage) = session(work, launcher: launcher, user: workUser)
        let (inPersonal, personalPage) = session(personal, launcher: launcher, user: personalUser)

        workPage.followNonWebLink(to: "mailto:a@example.test")
        await inWork.session.appLinks.settled()
        workPage.followNonWebLink(to: "mailto:b@example.test")
        await inWork.session.appLinks.settled()
        personalPage.followNonWebLink(to: "mailto:c@example.test")
        await inPersonal.session.appLinks.settled()

        #expect(workUser.asked.count == 1)
        #expect(personalUser.asked == [AppLinkPrompt(profileID: personal, scheme: URLScheme("mailto")!, app: mail,
                                                     requestedBy: "news.example")])
        #expect(launcher.openedAddresses == ["mailto:a@example.test", "mailto:b@example.test"])
        #expect(inPersonal.session.appLinks.permissions.appLinks == [])
    }

    @Test func aRememberedRefusalOpensNothingAndStaysSilentUntilItIsRevoked() async {
        let launcher = FakeLauncher()
        let user = FakeUser(neverOpen, open)
        let (fixture, page) = session(launcher: launcher, user: user)
        let permissions = fixture.session.appLinks.permissions

        page.followNonWebLink(to: "zoommtg://zoom.us/join")
        page.followNonWebLink(to: "mailto:a@example.test")
        await fixture.session.appLinks.settled()
        page.followNonWebLink(to: "mailto:b@example.test")
        await fixture.session.appLinks.settled()
        #expect(user.asked.map(\.scheme.rawValue) == ["mailto"])
        #expect(permissions.appLinkDecision(for: URLScheme("mailto")!) == .deny)
        #expect(launcher.opened.isEmpty)

        permissions.revokeAppLink(URLScheme("mailto")!)
        page.followNonWebLink(to: "mailto:c@example.test")
        await fixture.session.appLinks.settled()
        #expect(user.asked.map(\.scheme.rawValue) == ["mailto", "mailto"])
        #expect(launcher.openedAddresses == ["mailto:c@example.test"])
    }

    @Test func aSchemeNoAppTakesGetsARefusalAndNothingOpens() async {
        let launcher = FakeLauncher()
        let user = FakeUser(alwaysOpen)
        let (fixture, page) = session(launcher: launcher, user: user)

        page.followNonWebLink(to: "nothing-handles-this://x")
        await fixture.session.appLinks.settled()

        #expect(user.asked.isEmpty)
        #expect(user.refused == [AppLinkRefusal(profileID: work, scheme: URLScheme("nothing-handles-this")!,
                                                requestedBy: "news.example")])
        #expect(launcher.opened.isEmpty)
        #expect(fixture.session.appLinks.permissions.appLinks == [])
    }

    @Test func aRememberedAllowDoesNotOpenAnAppThatIsGone() async {
        let launcher = FakeLauncher()
        let user = FakeUser()
        let (fixture, page) = session(launcher: launcher, user: user)
        fixture.session.appLinks.permissions.rememberAppLink(.allow, for: URLScheme("slack")!, now: at)
        launcher.apps[URLScheme("slack")!] = nil

        page.followNonWebLink(to: "slack://channel?team=T1")
        await fixture.session.appLinks.settled()

        #expect(launcher.opened.isEmpty)
        #expect(user.refused.map(\.scheme.rawValue) == ["slack"])
    }

    @Test func aPageCannotOpenAnAppWhenNobodyIsThereToAskOrNothingCanOpen() async {
        let fixture = SessionFixture()
        fixture.visit("https://news.example")
        let page = fixture.selectedPage!

        page.followNonWebLink(to: "mailto:a@example.test")
        await fixture.session.appLinks.settled()
        #expect(fixture.session.appLinks.permissions.appLinks == [])

        let launcher = FakeLauncher()
        fixture.session.appLinks.handlers = AppLinkHandlers(launcher: launcher)
        page.followNonWebLink(to: "mailto:a@example.test")
        await fixture.session.appLinks.settled()
        #expect(launcher.opened.isEmpty)
    }

    @Test func aLinkFromABackgroundTabOrAPopupIsAskedAboutLikeAnyOther() async throws {
        let launcher = FakeLauncher()
        let user = FakeUser(dontOpen, dontOpen)
        let (fixture, _) = session(launcher: launcher, user: user)
        let blankID = fixture.clickTargetBlankLink(in: fixture.selectedPage, to: URL(string: "https://docs.example/")!)
        fixture.pages[blankID]?.followNonWebLink(to: "mailto:a@example.test")
        await fixture.session.appLinks.settled()
        let (_, popupPage) = fixture.openPopup(from: fixture.selectedPage, to: URL(string: "https://accounts.example/signin")!)
        popupPage.followNonWebLink(to: "slack://channel?team=T1")
        await fixture.session.appLinks.settled()

        #expect(user.asked.map(\.scheme.rawValue) == ["mailto", "slack"])
        #expect(user.asked.map(\.requestedBy) == ["docs.example", "accounts.example"])
        #expect(launcher.opened.isEmpty)
    }

    @Test func aPageThatFiresTheSameSchemeAgainWhileAQuestionIsOpenGetsOneQuestion() async {
        let launcher = FakeLauncher()
        let fixture = SessionFixture()
        fixture.visit("https://news.example")
        let page = fixture.selectedPage!
        var asked = 0
        var release: CheckedContinuation<Void, Never>?
        fixture.session.appLinks.handlers = AppLinkHandlers(launcher: launcher, prompt: { _ in
            asked += 1
            await withCheckedContinuation { release = $0 }
            return PermissionAnswer(decision: .allow, remember: false)
        })

        for _ in 0..<20 {
            page.followNonWebLink(to: "mailto:a@example.test")
        }
        await Task.yield()
        await Task.yield()
        release?.resume()
        await fixture.session.appLinks.settled()

        #expect(asked == 1)
        #expect(launcher.openedAddresses == ["mailto:a@example.test"])
    }

    @Test func aFailedOpenIsReportedNamingTheApp() async {
        struct Refused: Error {}
        let launcher = FakeLauncher()
        launcher.failure = Refused()
        let fixture = SessionFixture()
        var failures: [ExternalApp] = []
        fixture.session.appLinks.handlers = AppLinkHandlers(
            launcher: launcher, prompt: { _ in open }, openFailure: { app, _ in failures.append(app) })

        let outcome = await fixture.session.appLinks.handle(mailto, requestedBy: nil)

        #expect(outcome == .failed)
        #expect(failures == [mail])
    }

    @Test func theOutcomeNamesWhatHappened() async {
        let launcher = FakeLauncher()
        let user = FakeUser(open, dontOpen)
        let gate = AppLinkGate(profileID: work)
        gate.handlers = user.handlers(launcher)

        #expect(await gate.handle(slackLink, requestedBy: nil) == .opened(slack))
        #expect(await gate.handle(mailto, requestedBy: nil) == .declined)
        #expect(await gate.handle(NonWebLink(URL(string: "nope://x")!)!, requestedBy: nil) == .noApp)
    }

    @Test func choicesAreKeptInTheProfilesDatabaseAndNotInAnotherProfilesOne() async throws {
        let first = try ProfileDatabase.inMemory()
        let other = try ProfileDatabase.inMemory()
        let launcher = FakeLauncher()
        let user = FakeUser(alwaysOpen)
        let gate = AppLinkGate(profileID: work, permissions: SitePermissions(database: first))
        gate.handlers = user.handlers(launcher)
        _ = await gate.handle(mailto, requestedBy: nil)

        let relaunched = AppLinkGate(profileID: work, permissions: SitePermissions(database: first))
        let relaunchedUser = FakeUser()
        relaunched.handlers = relaunchedUser.handlers(launcher)
        #expect(await relaunched.handle(mailto, requestedBy: nil) == .opened(mail))
        #expect(relaunchedUser.asked.isEmpty)

        let otherProfile = AppLinkGate(profileID: personal, permissions: SitePermissions(database: other))
        otherProfile.handlers = relaunchedUser.handlers(launcher)
        #expect(await otherProfile.handle(mailto, requestedBy: nil) == .declined)
        #expect(relaunchedUser.asked.count == 1)
    }

    @Test func withoutADatabaseAChoiceLastsOnlyForTheRun() async {
        let launcher = FakeLauncher()
        let user = FakeUser(alwaysOpen)
        let gate = AppLinkGate(profileID: work, permissions: SitePermissions(database: nil))
        gate.handlers = user.handlers(launcher)

        _ = await gate.handle(mailto, requestedBy: nil)
        #expect(gate.permissions.appLinks.map(\.scheme.rawValue) == ["mailto"])

        let nextRun = AppLinkGate(profileID: work, permissions: SitePermissions(database: nil))
        #expect(nextRun.permissions.appLinks == [])
    }

    @Test func reviewingAndRevokingTheChoicesLeavesTheSitePermissionsAlone() throws {
        let database = try ProfileDatabase.inMemory()
        let permissions = SitePermissions(database: database)
        let meet = SiteOrigin(identifier: "https://meet.example")!
        permissions.remember(.allow, for: [.camera], at: meet, now: at)
        permissions.rememberAppLink(.allow, for: URLScheme("slack")!, now: at)
        permissions.rememberAppLink(.deny, for: URLScheme("mailto")!, now: at.addingTimeInterval(1))

        #expect(permissions.appLinks == [
            AppLinkChoice(scheme: URLScheme("mailto")!, decision: .deny, decidedAt: at.addingTimeInterval(1)),
            AppLinkChoice(scheme: URLScheme("slack")!, decision: .allow, decidedAt: at),
        ])

        permissions.revokeAppLink(URLScheme("mailto")!)
        let reread = SitePermissions(database: database)
        #expect(reread.appLinks.map(\.scheme.rawValue) == ["slack"])
        #expect(reread.all.map(\.id) == ["https://meet.example camera"])

        permissions.revokeAll()
        let empty = SitePermissions(database: database)
        #expect(empty.appLinks == [])
        #expect(empty.all == [])
    }
}

@Suite struct URLSchemeTests {
    @Test func aSchemeIsLowerCasedAndMustBeWrittenAsAURLSchemeIs() {
        #expect(URLScheme("MailTo")?.rawValue == "mailto")
        #expect(URLScheme("x-apple.systempreferences+v2")?.rawValue == "x-apple.systempreferences+v2")
        #expect(URLScheme("") == nil)
        #expect(URLScheme("1password") == nil)
        #expect(URLScheme("my scheme") == nil)
        #expect(URLScheme("é") == nil)
    }

    @Test func aLinkNeedsAScheme() {
        #expect(NonWebLink(URL(string: "SLACK://channel")!)?.scheme.rawValue == "slack")
        #expect(NonWebLink(URL(string: "relative/path")!) == nil)
    }
}
