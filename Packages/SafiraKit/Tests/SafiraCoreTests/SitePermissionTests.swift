// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import Testing

@Suite struct SiteOriginTests {
    @Test func anOriginIsWrittenAsSchemeHostAndPortWithoutTheDefaultPort() throws {
        #expect(try #require(SiteOrigin(scheme: "https", host: "example.com", port: 0)).identifier == "https://example.com")
        #expect(try #require(SiteOrigin(scheme: "https", host: "example.com", port: 8443)).identifier == "https://example.com:8443")
        #expect(try #require(SiteOrigin(scheme: "http", host: "::1", port: 3000)).identifier == "http://[::1]:3000")
    }

    @Test func letterCaseDoesNotMakeAnotherOrigin() {
        #expect(SiteOrigin(scheme: "HTTPS", host: "Example.COM") == SiteOrigin(scheme: "https", host: "example.com"))
    }

    @Test func theSchemeAndThePortMakeAnotherOrigin() {
        #expect(SiteOrigin(scheme: "http", host: "example.com") != SiteOrigin(scheme: "https", host: "example.com"))
        #expect(SiteOrigin(scheme: "https", host: "example.com", port: 8443) != SiteOrigin(scheme: "https", host: "example.com"))
    }

    @Test func aStoredOriginReadsBackAsTheSameOrigin() {
        for text in ["https://example.com", "https://example.com:8443", "http://[::1]:3000", "http://localhost:51234"] {
            #expect(SiteOrigin(identifier: text)?.identifier == text)
        }
    }

    @Test func textWithoutASchemeOrAHostIsNoOrigin() {
        #expect(SiteOrigin(identifier: "example.com") == nil)
        #expect(SiteOrigin(identifier: "file:///tmp/page.html") == nil)
        #expect(SiteOrigin(scheme: "", host: "example.com") == nil)
        #expect(SiteOrigin(scheme: "https", host: "") == nil)
    }
}

@Suite struct PermissionRuleTests {
    private func verdict(_ kinds: [PermissionKind], _ remembered: [PermissionKind: PermissionDecision]) -> PermissionVerdict {
        PermissionRule.verdict(requesting: kinds) { remembered[$0] }
    }

    @Test func nothingIsAllowedByDefaultSoTheUserIsAskedAboutEverythingRequested() {
        #expect(verdict([.camera], [:]) == .ask([.camera]))
        #expect(verdict([.camera, .microphone], [:]) == .ask([.camera, .microphone]))
        #expect(verdict([.location], [:]) == .ask([.location]))
    }

    @Test func aRememberedAllowAnswersWithoutAsking() {
        #expect(verdict([.camera], [.camera: .allow]) == .allow)
        #expect(verdict([.camera, .microphone], [.camera: .allow, .microphone: .allow]) == .allow)
    }

    @Test func aRememberedDenialAnswersWithoutAskingAndRefusesTheWholeRequest() {
        #expect(verdict([.location], [.location: .deny]) == .deny)
        #expect(verdict([.camera, .microphone], [.camera: .deny]) == .deny)
        #expect(verdict([.camera, .microphone], [.camera: .allow, .microphone: .deny]) == .deny)
    }

    @Test func aRequestForMoreThanIsRememberedAsksOnlyAboutTheRest() {
        #expect(verdict([.camera, .microphone], [.camera: .allow]) == .ask([.microphone]))
        #expect(verdict([.camera, .microphone], [.microphone: .allow]) == .ask([.camera]))
    }

    @Test func aDecisionAboutOneCapabilityDoesNotAnswerAnother() {
        #expect(verdict([.microphone], [.camera: .allow]) == .ask([.microphone]))
        #expect(verdict([.location], [.camera: .allow, .microphone: .allow]) == .ask([.location]))
    }

    @Test func aRequestForNothingIsDenied() {
        #expect(verdict([], [.camera: .allow]) == .deny)
    }
}

@Suite struct RequestedWindowTests {
    @Test func aWindowOpenedWithDimensionsIsAFloatingPanel() {
        #expect(RequestedWindow(width: 480, height: 640).opensFloatingPanel)
        #expect(RequestedWindow(width: 480).opensFloatingPanel)
        #expect(RequestedWindow(height: 640).opensFloatingPanel)
    }

    @Test func aWindowOpenedWithoutDimensionsIsALinkForABackgroundTab() {
        #expect(!RequestedWindow().opensFloatingPanel)
    }

    @Test func thePanelKeepsTheAskedSizeWithinWhatASignInFormFitsAndTheScreenShows() {
        #expect(RequestedWindow(width: 480, height: 640).panelSize == (480, 640))
        #expect(RequestedWindow(width: 100, height: 100).panelSize == (320, 360))
        #expect(RequestedWindow(width: 4000, height: 4000).panelSize == (900, 900))
        #expect(RequestedWindow(width: 600).panelSize == (600, 640))
        #expect(RequestedWindow(height: 500).panelSize == (500, 500))
    }
}
