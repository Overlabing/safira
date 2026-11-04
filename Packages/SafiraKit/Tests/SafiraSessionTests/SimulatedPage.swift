// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession

/// A page with a back-forward list, standing in for a web view. It counts every load, reload and restoration it is
/// asked for. Its navigation state is its back-forward list, encoded.
@MainActor
final class SimulatedPage: WebPageHandle {
    private(set) var loadCount = 0
    private(set) var reloadCount = 0
    private(set) var restoreCount = 0
    private(set) var isClosed = false
    /// Makes `restore` fail, as the engine does with a state it cannot read.
    var refusesNavigationState = false
    private var history: [Entry] = []
    private var index = -1
    private var isPlayingMedia = false
    private var sensitiveHistory = SensitiveHistory<UUID>()
    var onStateChange: (@MainActor (PageState) -> Void)?
    var onNewTab: (@MainActor (NewTabRequest) -> Void)?

    private struct Entry: Codable {
        var id = UUID()
        let url: URL
    }

    private struct NavigationState: Codable {
        let history: [Entry]
        let index: Int
    }

    var state: PageState {
        PageState(url: history.indices.contains(index) ? history[index].url : nil,
                  canGoBack: index > 0, canGoForward: index < history.count - 1, isPlayingMedia: isPlayingMedia)
    }

    var navigationState: Data? {
        guard !history.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(NavigationState(history: history, index: index))
    }

    var sensitiveContent: SensitiveContent {
        sensitiveHistory.content(of: history.map(\.id))
    }

    func load(_ url: URL) {
        loadCount += 1
        navigate(to: url)
    }

    func restore(_ navigationState: Data) -> Bool {
        restoreCount += 1
        guard !refusesNavigationState,
              let saved = try? JSONDecoder().decode(NavigationState.self, from: navigationState) else { return false }
        history = saved.history
        index = saved.index
        onStateChange?(state)
        return true
    }

    /// The shown page gets a password field.
    func showPasswordField() {
        sensitiveHistory.mark(history[index].id, .passwordField)
    }

    /// The user submits a form that posts to `url`.
    func submitPostForm(to url: URL) {
        navigate(to: url)
        sensitiveHistory.mark(history[index].id, .postBody)
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
        history.append(Entry(url: url))
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
    /// Applied to every page as it is created.
    var preparePage: (SimulatedPage) -> Void = { _ in }

    init(searchEngine: SearchEngine? = nil, osBuild: String = "26A434") {
        let id = ProfileID(rawValue: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!)
        session = ProfileSession(profile: Profile(id: id, name: "Personal", searchEngine: searchEngine),
                                 osBuild: osBuild) { [unowned self] tabID in
            let page = SimulatedPage()
            preparePage(page)
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
