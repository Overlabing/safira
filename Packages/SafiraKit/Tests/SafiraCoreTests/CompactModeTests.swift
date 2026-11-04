// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
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

@Test func compactModeSurvivesARelaunchButARevealedSidebarDoesNot() throws {
    let suite = "CompactModeTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    var presentation = SidebarPresentation(isCompact: true)
    presentation.reveal()

    CompactModeStore(defaults: defaults).save(presentation)
    let relaunched = CompactModeStore(defaults: defaults).load()

    #expect(relaunched.isCompact == true)
    #expect(relaunched.isRevealed == false)
}

@Test func aFreshInstallStartsOutsideCompactMode() throws {
    let suite = "CompactModeTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(CompactModeStore(defaults: defaults).load().isCompact == false)
}

@Test func theRegistryListsCompactModeAsOffAndChangedFromTheViewMenu() throws {
    let entry = try #require(SidebarPresentation.defaultEntries.first)

    #expect(SidebarPresentation.defaultEntries.count == 1)
    #expect(entry.id == "window.compactMode")
    #expect(entry.title == "Compact Mode")
    #expect(entry.value == "Off")
    #expect(entry.whereToChange == "View menu")
}
