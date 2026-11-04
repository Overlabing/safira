// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession
import SafiraStore
import Testing

/// A fresh Application Support folder for one test, removed when the test ends.
private final class TemporaryRoot {
    let layout = StoreLayout(root: FileManager.default.temporaryDirectory
        .appending(path: "safira-\(UUID().uuidString)", directoryHint: .isDirectory))

    deinit { try? FileManager.default.removeItem(at: layout.root) }
}

private let work = ProfileID(rawValue: UUID(uuidString: "0B4E2C1A-5D3F-4E8B-9A7C-1F2E3D4C5B6A")!)
private let personal = ProfileID(rawValue: UUID(uuidString: "7C8D9E0F-1A2B-4C3D-8E5F-6A7B8C9D0E1F")!)
private let meet = SiteOrigin(identifier: "https://meet.example")!
private let shop = SiteOrigin(identifier: "https://shop.example")!
private let at = Date(timeIntervalSince1970: 1_700_000_000)

@MainActor
@Suite struct SitePermissionsTests {
    private func permissions(_ profile: ProfileID, in root: TemporaryRoot) throws -> SitePermissions {
        SitePermissions(database: try ProfileDatabase(file: root.layout.profileDatabaseFile(for: profile)))
    }

    @Test func aSiteIsAskedUntilTheUserChoosesToRememberAndThenItIsNot() throws {
        let permissions = SitePermissions()
        #expect(permissions.verdict(requesting: [.camera, .microphone], at: meet) == .ask([.camera, .microphone]))

        permissions.remember(.allow, for: [.camera, .microphone], at: meet, now: at)

        #expect(permissions.verdict(requesting: [.camera, .microphone], at: meet) == .allow)
        #expect(permissions.verdict(requesting: [.camera], at: shop) == .ask([.camera]))
        #expect(permissions.verdict(requesting: [.location], at: meet) == .ask([.location]))
    }

    @Test func aRememberedDecisionIsReplacedByTheNextOneForTheSameSiteAndCapability() {
        let permissions = SitePermissions()
        permissions.remember(.allow, for: [.camera], at: meet, now: at)
        permissions.remember(.deny, for: [.camera], at: meet, now: at.addingTimeInterval(5))

        #expect(permissions.all == [
            SitePermission(origin: meet, kind: .camera, decision: .deny, decidedAt: at.addingTimeInterval(5)),
        ])
        #expect(permissions.verdict(requesting: [.camera], at: meet) == .deny)
    }

    @Test func revokingMakesTheSiteAskAgainAndLeavesTheOthers() {
        let permissions = SitePermissions()
        permissions.remember(.allow, for: [.camera, .microphone], at: meet, now: at)
        permissions.remember(.deny, for: [.location], at: shop, now: at)

        permissions.revoke(.camera, at: meet)

        #expect(permissions.verdict(requesting: [.camera], at: meet) == .ask([.camera]))
        #expect(permissions.verdict(requesting: [.microphone], at: meet) == .allow)
        #expect(permissions.verdict(requesting: [.location], at: shop) == .deny)
        permissions.revokeAll()
        #expect(permissions.all == [])
    }

    @Test func aDecisionRememberedInOneProfileDoesNotApplyInAnotherAndSurvivesARelaunch() throws {
        let root = TemporaryRoot()
        let inWork = try permissions(work, in: root)
        let inPersonal = try permissions(personal, in: root)

        inWork.remember(.allow, for: [.camera], at: meet, now: at)

        #expect(inWork.verdict(requesting: [.camera], at: meet) == .allow)
        #expect(inPersonal.verdict(requesting: [.camera], at: meet) == .ask([.camera]))
        #expect(inPersonal.all == [])
        let relaunchedWork = try permissions(work, in: root)
        let relaunchedPersonal = try permissions(personal, in: root)
        #expect(relaunchedWork.all == [SitePermission(origin: meet, kind: .camera, decision: .allow, decidedAt: at)])
        #expect(relaunchedPersonal.all == [])
    }

    @Test func aRevocationIsKeptAcrossARelaunch() throws {
        let root = TemporaryRoot()
        let first = try permissions(work, in: root)
        first.remember(.allow, for: [.camera, .location], at: meet, now: at)
        first.revoke(.camera, at: meet)

        let relaunched = try permissions(work, in: root)

        #expect(relaunched.all == [SitePermission(origin: meet, kind: .location, decision: .allow, decidedAt: at)])
    }

    @Test func aDecisionThatCannotBeSavedIsNotRememberedAndTheErrorIsReported() throws {
        let root = TemporaryRoot()
        let file = root.layout.profileDatabaseFile(for: work)
        _ = try ProfileDatabase(file: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: file.path(percentEncoded: false))
        var reported: [String] = []
        let permissions = SitePermissions(database: try ProfileDatabase(file: file)) { message, _ in reported.append(message) }

        permissions.remember(.allow, for: [.camera], at: meet, now: at)

        #expect(permissions.all == [])
        #expect(permissions.verdict(requesting: [.camera], at: meet) == .ask([.camera]))
        #expect(reported == ["The site permission could not be saved"])
    }
}
