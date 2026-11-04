// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import LinkRouting
import SafiraCore
import Testing

@MainActor
private final class RecordingDestination: LinkDestination {
    var profiles: [Profile]
    private(set) var opened: [(url: String, profile: ProfileID)] = []

    init(profiles: [Profile]) {
        self.profiles = profiles
    }

    func open(_ url: URL, in profile: ProfileID) -> Bool {
        guard profiles.contains(where: { $0.id == profile }) else { return false }
        opened.append((url.absoluteString, profile))
        return true
    }
}

/// Holds each question open until the test answers it, so the order of events is under the test's control.
@MainActor
private final class ScriptedChooser: ProfileChoosing {
    private(set) var asked: [IncomingLink] = []
    private(set) var offered: [[Profile]] = []
    private var waiting: [CheckedContinuation<ProfileID?, Never>] = []

    func chooseProfile(for link: IncomingLink, among profiles: [Profile]) async -> ProfileID? {
        asked.append(link)
        offered.append(profiles)
        return await withCheckedContinuation { waiting.append($0) }
    }

    func answer(_ choice: ProfileID?) {
        waiting.removeFirst().resume(returning: choice)
    }

    /// Lets the coordinator run until it asks, or until it has nothing left to do.
    func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }
}

@MainActor
private func makeLog(enabled: Bool) -> (LinkChoiceLog, URL) {
    let file = FileManager.default.temporaryDirectory.appending(path: "safira-\(UUID().uuidString)/link-choices.jsonl")
    return (LinkChoiceLog(file: file, isEnabled: enabled), file)
}

@MainActor
@Suite struct ExternalLinkCoordinatorTests {
    @Test func aLinkWithOneProfileOpensThereWithoutAsking() async {
        let destination = RecordingDestination(profiles: [workProfile])
        let chooser = ScriptedChooser()
        let coordinator = ExternalLinkCoordinator(destination: destination, chooser: chooser)

        coordinator.receive(exampleLink)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.url) == ["https://example.com/a/path?q=secret#frag"])
        #expect(destination.opened.map(\.profile) == [workProfile.id])
        #expect(chooser.asked.isEmpty)
    }

    @Test func aLinkWithSeveralProfilesOpensInTheOneTheUserChooses() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = ExternalLinkCoordinator(destination: destination, chooser: chooser)

        coordinator.receive(exampleLink)
        await chooser.settle()
        #expect(destination.opened.isEmpty)
        #expect(chooser.offered == [[workProfile, homeProfile]])

        chooser.answer(homeProfile.id)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.profile) == [homeProfile.id])
    }

    @Test func dismissingTheQuestionOpensNothing() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = ExternalLinkCoordinator(destination: destination, chooser: chooser)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(nil)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.isEmpty)
    }

    @Test func aLinkThatArrivesWhileTheQuestionIsOpenWaitsForItsTurn() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = ExternalLinkCoordinator(destination: destination, chooser: chooser)
        let second = IncomingLink(url: URL(string: "https://swift.org/")!)

        coordinator.receive(exampleLink)
        await chooser.settle()
        coordinator.receive(second)
        await chooser.settle()
        #expect(chooser.asked.map(\.url.host) == ["example.com"])

        chooser.answer(workProfile.id)
        await chooser.settle()
        #expect(chooser.asked.map(\.url.host) == ["example.com", "swift.org"])
        chooser.answer(homeProfile.id)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.url) == ["https://example.com/a/path?q=secret#frag", "https://swift.org/"])
        #expect(destination.opened.map(\.profile) == [workProfile.id, homeProfile.id])
    }

    @Test func aProfileDeletedWhileTheQuestionWasOpenReceivesNothing() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let (log, file) = makeLog(enabled: true)
        let coordinator = ExternalLinkCoordinator(destination: destination, chooser: chooser, choiceLog: log)

        coordinator.receive(exampleLink)
        await chooser.settle()
        destination.profiles = [workProfile]
        chooser.answer(homeProfile.id)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test(arguments: ["mailto:someone@example.com", "slack://open", "ftp://example.com/file"])
    func linksSafiraDoesNotHandleAreDropped(address: String) async throws {
        let destination = RecordingDestination(profiles: [workProfile])
        let chooser = ScriptedChooser()
        let coordinator = ExternalLinkCoordinator(destination: destination, chooser: chooser)

        coordinator.receive(IncomingLink(url: try #require(URL(string: address))))
        await coordinator.waitUntilIdle()

        #expect(destination.opened.isEmpty)
        #expect(chooser.asked.isEmpty)
    }

    @Test func aLocalHTMLFileGoesThroughTheSameChoice() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let coordinator = ExternalLinkCoordinator(destination: destination, chooser: chooser)

        coordinator.receive(IncomingLink(url: URL(filePath: "/Users/someone/page.html")))
        await chooser.settle()
        chooser.answer(workProfile.id)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.url) == ["file:///Users/someone/page.html"])
    }

    @Test func aChoiceIsLoggedWithTheHostAndTheProfileOnlyWhenTheLogIsOn() async throws {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let (log, file) = makeLog(enabled: true)
        let coordinator = ExternalLinkCoordinator(destination: destination, chooser: chooser, choiceLog: log)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(workProfile.id)
        await coordinator.waitUntilIdle()

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written == "{\"host\":\"example.com\",\"profile\":\"11111111-1111-4111-8111-111111111111\"}\n")
    }

    @Test func nothingIsLoggedWhileTheLogIsOff() async {
        let destination = RecordingDestination(profiles: [workProfile, homeProfile])
        let chooser = ScriptedChooser()
        let (log, file) = makeLog(enabled: false)
        let coordinator = ExternalLinkCoordinator(destination: destination, chooser: chooser, choiceLog: log)

        coordinator.receive(exampleLink)
        await chooser.settle()
        chooser.answer(workProfile.id)
        await coordinator.waitUntilIdle()

        #expect(destination.opened.map(\.profile) == [workProfile.id])
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }
}
