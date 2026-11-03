// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession

/// A page with a back-forward list, standing in for a web view. It counts every load and reload it is asked for.
@MainActor
final class SimulatedPage: WebPageHandle {
    private(set) var loadCount = 0
    private(set) var reloadCount = 0
    private(set) var isClosed = false
    /// Every load the session asked for, in order, with the policy it asked for.
    private(set) var loads: [(url: URL, httpsFirst: Bool)] = []
    private(set) var shownWarnings: [InsecureConnectionWarning] = []
    private var history: [URL] = []
    private var index = -1
    private var isPlayingMedia = false
    var onStateChange: (@MainActor (PageState) -> Void)?
    var onNewTab: (@MainActor (NewTabRequest) -> Void)?
    var onLoadFailure: (@MainActor (LoadFailure) -> Void)?
    var onContinueOverHTTP: (@MainActor () -> Void)?

    var state: PageState {
        PageState(url: history.indices.contains(index) ? history[index] : nil,
                  canGoBack: index > 0, canGoForward: index < history.count - 1, isPlayingMedia: isPlayingMedia)
    }

    func load(_ url: URL, httpsFirst: Bool) {
        loadCount += 1
        loads.append((url, httpsFirst))
        navigate(to: url)
    }

    func showInsecureConnectionWarning(_ warning: InsecureConnectionWarning) {
        shownWarnings.append(warning)
    }

    /// The platform reports that the navigation to `url` failed with the given NSURLError code.
    func failLoad(of url: URL, code: URLError.Code) {
        onLoadFailure?(LoadFailure(url: url, domain: NSURLErrorDomain, code: code.rawValue))
    }

    /// The user presses "Continue over HTTP" on the warning page.
    func pressContinueOverHTTP() {
        onContinueOverHTTP?()
    }

    /// A navigation the page starts itself, as when the user clicks a link.
    func followLink(to url: URL) {
        navigate(to: url)
    }

    /// A link the user opens with ⌘: the page asks for a new Tab and stays where it is.
    func commandClickLink(to url: URL) {
        onNewTab?(.address(url))
    }

    func setPlayingMedia(_ playing: Bool) {
        isPlayingMedia = playing
        onStateChange?(state)
    }

    func goBack() {
        precondition(index > 0, "the session asked for back with nothing behind")
        index -= 1
        onStateChange?(state)
    }

    func goForward() {
        precondition(index < history.count - 1, "the session asked for forward with nothing ahead")
        index += 1
        onStateChange?(state)
    }

    func reload() {
        reloadCount += 1
        onStateChange?(state)
    }

    func close() {
        isClosed = true
    }

    private func navigate(to url: URL) {
        history.removeSubrange((index + 1)...)
        history.append(url)
        index += 1
        onStateChange?(state)
    }
}

/// A Profile session whose pages are simulated, with the pages it created, in creation order.
@MainActor
final class SessionFixture {
    private(set) var pages: [TabID: SimulatedPage] = [:]
    private(set) var createdPageCount = 0
    private(set) var session: ProfileSession!

    init(searchEngine: SearchEngine? = nil) {
        let id = ProfileID(rawValue: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
        session = ProfileSession(profile: Profile(id: id, name: "Personal", searchEngine: searchEngine)) { [unowned self] tabID in
            let page = SimulatedPage()
            pages[tabID] = page
            createdPageCount += 1
            return page
        }
    }

    /// A `target=_blank` link clicked in `page`: the engine builds the new page itself and loads the link in it.
    @discardableResult
    func clickTargetBlankLink(in page: SimulatedPage?, to url: URL) -> TabID {
        let id = TabID()
        let newPage = SimulatedPage()
        pages[id] = newPage
        page?.onNewTab?(.page(id, newPage))
        newPage.followLink(to: url)
        return id
    }

    var selectedPage: SimulatedPage? {
        session.selectedTabID.flatMap { pages[$0] }
    }

    var addresses: [String?] {
        session.tabs.map { $0.address?.absoluteString }
    }
}
