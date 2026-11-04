// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation
import SafiraCore
import SafiraSession
import Testing

@MainActor
private final class LoadingPage: WebPageHandle {
    var state = PageState()
    var onStateChange: (@MainActor (PageState) -> Void)?
    var onNewTab: (@MainActor (NewTabRequest) -> Void)?
    let navigationState: Data? = nil
    let sensitiveContent: SensitiveContent = []

    func restore(_ navigationState: Data) -> Bool { false }

    func load(_ url: URL) {
        state = PageState(url: url, isLoading: true)
        onStateChange?(state)
    }

    func finishLoading() {
        state.isLoading = false
        onStateChange?(state)
    }

    func goBack() {}
    func goForward() {}
    func reload() {}
    func close() {}
}

@MainActor
@Suite struct DiagnosticTabCountsTests {
    @Test func tabsAreCountedByStateWithoutReadingTheirAddresses() {
        var pages: [TabID: LoadingPage] = [:]
        let session = ProfileSession(profile: Profile(id: ProfileID(rawValue: UUID()), name: "Work")) { id in
            let page = LoadingPage()
            pages[id] = page
            return page
        }
        session.openNewTab()
        #expect(session.diagnosticTabCounts == TabCounts(blank: 1, loading: 0, loaded: 0))

        session.submitCommandBar("example.com")
        let first = session.tabs[0].id
        session.openNewTab()
        session.submitCommandBar("swift.org")
        session.openNewTab()
        #expect(session.diagnosticTabCounts == TabCounts(blank: 1, loading: 2, loaded: 0))

        pages[first]?.finishLoading()
        #expect(session.diagnosticTabCounts == TabCounts(blank: 1, loading: 1, loaded: 1))
    }
}
