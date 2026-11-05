// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Preferences
import SafiraCore
import Testing

@Test func theSidebarIsDockedUntilCompactModeIsTurnedOn() {
    let presentation = SidebarPresentation()

    #expect(presentation.isCompact == false)
    #expect(presentation.isSidebarShown == true)
}

@Test func compactModeHidesTheSidebar() {
    var presentation = SidebarPresentation()
    presentation.toggleCompact()

    #expect(presentation.isCompact == true)
    #expect(presentation.isSidebarShown == false)
}

@Test func theLeftEdgeRevealsTheSidebarAndLeavingItHidesItAgain() {
    var presentation = SidebarPresentation(isCompact: true)

    presentation.reveal()
    #expect(presentation.isSidebarShown == true)
    #expect(presentation.isRevealed == true)

    presentation.hide()
    #expect(presentation.isSidebarShown == false)
}

@Test func theShortcutRevealsTheSidebarThenHidesIt() {
    var presentation = SidebarPresentation(isCompact: true)

    presentation.toggleRevealed()
    #expect(presentation.isRevealed == true)

    presentation.toggleRevealed()
    #expect(presentation.isRevealed == false)
}

@Test func revealingDoesNothingOutsideCompactMode() {
    var presentation = SidebarPresentation()

    presentation.reveal()
    presentation.toggleRevealed()

    #expect(presentation.isRevealed == false)
    #expect(presentation.isSidebarShown == true)
}

@Test func turningCompactModeOffOrOnStartsWithTheSidebarNotRevealed() {
    var presentation = SidebarPresentation(isCompact: true)
    presentation.reveal()

    presentation.setCompact(false)
    #expect(presentation.isRevealed == false)

    presentation.setCompact(true)
    #expect(presentation.isRevealed == false)
}

@Test func compactModeSurvivesARelaunchButARevealedSidebarDoesNot() {
    let store = InMemoryKeyValueStore()
    var presentation = SidebarPresentation(isCompact: true)
    presentation.reveal()

    CompactModeStore(store: store).save(presentation)
    let relaunched = CompactModeStore(store: store).load(unreadable: { _ in })

    #expect(relaunched.isCompact == true)
    #expect(relaunched.isRevealed == false)
}

@Test func compactModeIsWhatIsSavedNotWhetherTheSidebarWasRevealed() {
    let store = InMemoryKeyValueStore()
    let presentation = SidebarPresentation(isCompact: true)
    #expect(presentation.isRevealed == false)

    CompactModeStore(store: store).save(presentation)
    let relaunched = CompactModeStore(store: store).load(unreadable: { _ in })

    #expect(relaunched == SidebarPresentation(isCompact: true))
    #expect(relaunched.isCompact == true)
    #expect(relaunched.isRevealed == false)
}

@Test func aFreshInstallStartsOutsideCompactMode() {
    #expect(CompactModeStore(store: InMemoryKeyValueStore()).load(unreadable: { _ in }).isCompact == false)
}

@Test func compactModeTheOldStoreKeptIsReadAfterTheMigration() throws {
    let (defaults, domain) = try scratchDefaults()
    defer { defaults.removePersistentDomain(forName: domain) }
    defaults.set(true, forKey: "window.compactMode")

    LegacyPreference.migrate([CompactModeStore.legacy], in: defaults, domain: domain)

    #expect(CompactModeStore(store: defaults).load(unreadable: { _ in }).isCompact == true)
    #expect(defaults.data(forKey: "window.compactMode") == Data("true".utf8))
}

@Test func theRegistryListsCompactModeAsOffAndChangedFromTheViewMenu() throws {
    let entry = try #require(SidebarPresentation.defaultEntries.first)

    #expect(SidebarPresentation.defaultEntries.count == 1)
    #expect(entry.id == "window.compactMode")
    #expect(entry.title == "Compact Mode")
    #expect(entry.value == "Off")
    #expect(entry.whereToChange == "View menu")
}
