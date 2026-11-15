// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore

/// Find in page: the find bar of a window, searching the shown Tab's page. The text stays when the bar closes, so ⌘G
/// finds it again, as in Safari.
@MainActor
@Observable
public final class PageFind {
    public enum Result: Hashable, Sendable {
        /// Nothing searched yet: the text is empty.
        case empty
        case notFound
        /// The highlighted match is the `current`th of `count`, counting from the top of the page.
        case match(current: Int, count: Int)
        /// The engine found a match that the page's visible text does not show, as in a text field: no count.
        case uncounted
    }

    public private(set) var isShown = false
    public private(set) var text = ""
    public private(set) var result = Result.empty
    /// The session's shown Tab.
    @ObservationIgnored var shownTab: @MainActor () -> Tab? = { nil }
    /// The Tab the highlight is in.
    @ObservationIgnored private weak var searchedTab: Tab?
    /// Each search or step takes a number; an answer that comes back after a newer one started is dropped.
    @ObservationIgnored private var generation = 0

    init() {}

    /// Shows the bar, searching the shown Tab again for the text it already has.
    public func show() async {
        isShown = true
        await search(text)
    }

    /// The text changed: the first match from the top is highlighted.
    public func search(_ text: String) async {
        self.text = text
        let number = begin()
        guard let tab = shownTab(), tab.hasPage, !text.isEmpty else {
            searchedTab?.endFind()
            searchedTab = nil
            result = .empty
            return
        }
        searchedTab = tab
        let found = await tab.find(text, backwards: false)
        guard number == generation else { return }
        let count = found ? await tab.countMatches(of: text) : 0
        guard number == generation else { return }
        result = !found ? .notFound : count == 0 ? .uncounted : .match(current: 1, count: count)
    }

    /// ⌘G: the next match, back to the first after the last. Shows the bar if it was closed.
    public func next() async {
        await step(backwards: false)
    }

    /// ⇧⌘G: the previous match, round to the last before the first.
    public func previous() async {
        await step(backwards: true)
    }

    /// Hides the bar and the highlight; the text stays for the next ⌘G.
    public func close() {
        guard isShown || searchedTab != nil else { return }
        begin()
        isShown = false
        searchedTab?.endFind()
        searchedTab = nil
        result = .empty
    }

    private func step(backwards: Bool) async {
        let isSteppable = result != .empty && result != .notFound
        guard isShown, isSteppable, let tab = searchedTab, tab === shownTab() else {
            // A closed bar, another Tab, or nothing found yet: start over from the top.
            isShown = true
            await search(text)
            return
        }
        let number = begin()
        let found = await tab.find(text, backwards: backwards)
        guard number == generation else { return }
        switch (found, result) {
        case (false, _):
            result = .notFound
        case (true, .match(let current, let count)):
            let next = backwards ? (current + count - 2) % count + 1 : current % count + 1
            result = .match(current: next, count: count)
        case (true, _):
            result = .uncounted
        }
    }

    @discardableResult
    private func begin() -> Int {
        generation += 1
        return generation
    }
}
