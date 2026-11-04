// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import SafiraWeb
import Testing

/// What a Profile's web context answers to a camera, microphone or location request, and what it remembers. The page
/// side (WebKit calling the delegate) needs an app bundle that declares the usage descriptions and entitlements: the
/// test host has none, and WebKit then never asks, so that side is checked in the app itself.
@MainActor
@Suite(.serialized) struct SitePermissionDecisionTests {
    @MainActor final class Asked { var prompts: [PermissionPrompt] = [] }

    private let meet = SiteOrigin(identifier: "https://meet.example")!

    private func context(_ profile: ProfileID, answering answer: PermissionAnswer?, asked: Asked,
                         permissions: SitePermissions = SitePermissions()) -> ProfileWebContext {
        let context = ProfileWebContext(profileID: profile, permissions: permissions)
        if let answer {
            context.permissionPrompt = { @MainActor prompt in
                asked.prompts.append(prompt)
                return answer
            }
        }
        return context
    }

    @Test func theUsersAnswerIsRememberedOnlyWhenTheyAskForItAndThenTheSiteIsNotAskedAgain() async {
        let profile = ProfileID(rawValue: UUID())
        let asked = Asked()
        let remembering = context(profile, answering: PermissionAnswer(decision: .allow, remember: true), asked: asked)

        #expect(await remembering.permissionDecision(requesting: [.camera, .microphone], at: meet) == .allow)
        #expect(await remembering.permissionDecision(requesting: [.camera], at: meet) == .allow)
        #expect(asked.prompts == [PermissionPrompt(profileID: profile, origin: meet, kinds: [.camera, .microphone])])
        #expect(remembering.permissions.all.map(\.id) == ["https://meet.example camera", "https://meet.example microphone"])

        let onceAsked = Asked()
        let once = context(profile, answering: PermissionAnswer(decision: .allow, remember: false), asked: onceAsked)
        #expect(await once.permissionDecision(requesting: [.location], at: meet) == .allow)
        #expect(await once.permissionDecision(requesting: [.location], at: meet) == .allow)
        #expect(onceAsked.prompts.count == 2)
        #expect(once.permissions.all == [])
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aRememberedDenialRefusesWithoutAskingUntilItIsRevoked() async {
        let profile = ProfileID(rawValue: UUID())
        let asked = Asked()
        let web = context(profile, answering: PermissionAnswer(decision: .deny, remember: true), asked: asked)

        #expect(await web.permissionDecision(requesting: [.location], at: meet) == .deny)
        #expect(await web.permissionDecision(requesting: [.location], at: meet) == .deny)
        #expect(asked.prompts.count == 1)

        web.permissions.revoke(.location, at: meet)
        #expect(await web.permissionDecision(requesting: [.location], at: meet) == .deny)
        #expect(asked.prompts.count == 2)
        await removeDataStoreWhenReleased(profile)
    }

    @Test func aGrantInOneProfileIsNotAGrantInAnotherEvenForTheSameSite() async {
        let work = ProfileID(rawValue: UUID())
        let personal = ProfileID(rawValue: UUID())
        let workAsked = Asked()
        let personalAsked = Asked()
        let inWork = context(work, answering: PermissionAnswer(decision: .allow, remember: true), asked: workAsked)
        let inPersonal = context(personal, answering: PermissionAnswer(decision: .deny, remember: false), asked: personalAsked)

        #expect(await inWork.permissionDecision(requesting: [.camera], at: meet) == .allow)
        #expect(await inWork.permissionDecision(requesting: [.camera], at: meet) == .allow)
        #expect(await inPersonal.permissionDecision(requesting: [.camera], at: meet) == .deny)

        #expect(workAsked.prompts.count == 1)
        #expect(personalAsked.prompts == [PermissionPrompt(profileID: personal, origin: meet, kinds: [.camera])])
        #expect(inPersonal.permissions.all == [])
        await removeDataStoreWhenReleased(work)
        await removeDataStoreWhenReleased(personal)
    }

    @Test func aSecondSiteIsAskedEvenWhenAnotherOneWasAllowed() async {
        let profile = ProfileID(rawValue: UUID())
        let asked = Asked()
        let web = context(profile, answering: PermissionAnswer(decision: .allow, remember: true), asked: asked)
        let other = SiteOrigin(identifier: "https://other.example")!

        #expect(await web.permissionDecision(requesting: [.camera], at: meet) == .allow)
        #expect(await web.permissionDecision(requesting: [.camera], at: other) == .allow)

        #expect(asked.prompts.map(\.origin) == [meet, other])
        await removeDataStoreWhenReleased(profile)
    }

    @Test func withNobodyToAskARequestIsRefusedAndNothingIsRemembered() async {
        let profile = ProfileID(rawValue: UUID())
        let web = context(profile, answering: nil, asked: Asked())

        #expect(await web.permissionDecision(requesting: [.camera], at: meet) == .deny)
        #expect(web.permissions.all == [])
        await removeDataStoreWhenReleased(profile)
    }

    @Test func decisionsKeptInAProfilesDatabaseServeItsWebContextAfterARelaunch() async throws {
        let profile = ProfileID(rawValue: UUID())
        let database = try ProfileDatabase.inMemory()
        let first = context(profile, answering: PermissionAnswer(decision: .allow, remember: true), asked: Asked(),
                            permissions: SitePermissions(database: database))
        #expect(await first.permissionDecision(requesting: [.microphone], at: meet) == .allow)

        let asked = Asked()
        let relaunched = context(profile, answering: PermissionAnswer(decision: .deny, remember: false), asked: asked,
                                 permissions: SitePermissions(database: database))
        #expect(await relaunched.permissionDecision(requesting: [.microphone], at: meet) == .allow)
        #expect(asked.prompts == [])
        await removeDataStoreWhenReleased(profile)
    }
}
