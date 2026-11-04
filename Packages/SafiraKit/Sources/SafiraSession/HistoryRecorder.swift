// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraStore

/// What a Tab reports about the pages it shows, as far as history is concerned.
enum VisitEvent: Equatable {
    /// The Tab arrived at a new web address.
    case visited(URL)
    /// The page at the address has this title.
    case titled(String, URL)
}

/// Follows one Tab's page and says when history should hear of it. A visit is recorded with its address alone; the
/// title follows once the page has loaded, and only if the page holds no password field and was not reached by a
/// POST request (decision D1: such a page enters history by address only).
struct VisitTracker {
    private var address: URL?
    private var title: String?

    /// - Parameter restoredAddress: where a restored Tab already is, so that bringing it back is not a new visit.
    init(restoredAddress: URL? = nil) {
        address = restoredAddress
    }

    mutating func observe(_ state: PageState, sensitiveContent: @autoclosure () -> SensitiveContent) -> [VisitEvent] {
        var events: [VisitEvent] = []
        guard let url = state.url, Self.isWebAddress(url) else {
            if state.url != nil { address = nil }
            return events
        }
        if url != address {
            address = url
            title = nil
            events.append(.visited(url))
        }
        if !state.isLoading, let pageTitle = state.title, !pageTitle.isEmpty, pageTitle != title,
           sensitiveContent().isEmpty {
            title = pageTitle
            events.append(.titled(pageTitle, url))
        }
        return events
    }

    private static func isWebAddress(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}

/// Writes a Profile's history, one write after the other and off the main actor. A Profile without a recorder, such
/// as a Private window's, keeps no history.
@MainActor
final class HistoryRecorder {
    private let database: ProfileDatabase
    private var writing: Task<Void, Never>?
    var onError: (@MainActor (any Error) -> Void)?

    init(database: ProfileDatabase) {
        self.database = database
    }

    func record(_ event: VisitEvent) {
        let previous = writing
        writing = Task { [database, weak self] in
            await previous?.value
            do {
                switch event {
                case .visited(let url): try await database.recordVisit(to: url)
                case .titled(let title, let url): try await database.setTitle(title, ofLatestVisitTo: url)
                }
            } catch {
                self?.onError?(error)
            }
        }
    }

    /// Returns once everything recorded so far has reached the database.
    func settled() async {
        await writing?.value
    }
}
