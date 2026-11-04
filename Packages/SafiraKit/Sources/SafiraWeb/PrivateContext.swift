// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation
import SafiraCore
import SafiraSession

/// The owner of one Private window: a new non-persistent data store, a session with a single hidden Space, and no
/// database at all, so nothing it does can reach the disk. It is attached to a Profile only by name: it starts with that
/// Profile's search engine and nothing else, and it shares no data store, history or site permission with it.
///
/// Only the window that shows it holds it. `ProfileRegistry` makes it and forgets it, so nothing that searches the
/// Profiles' sessions (the Command bar, Matching tabs) can reach a Private window.
@MainActor
public final class PrivateContext: BrowsingContext {
    /// The Profile the window is attached to, as it was when the window opened.
    public let parent: Profile
    public let web: ProfileWebContext
    public let session: ProfileSession

    init(parent: Profile, searchEngine: SearchEngine?) {
        self.parent = parent
        let web = ProfileWebContext(privateWindowOf: parent.id)
        let session = ProfileSession(profileID: parent.id, settings: ProfileSettings(searchEngine: searchEngine),
                                     history: nil, hasSpaces: false) { [unowned web] in web.makePage(for: $0) }
        self.web = web
        self.session = session
    }

    /// Closes every page and empties the data store, as the window closes. Nothing is left to keep: the data store is
    /// released with its last page. A download still running is stopped and its partial file removed; the list of
    /// downloads was never saved (no database).
    public func close() async {
        await web.cancelDownloads()
        session.closeAllTabs()
        await web.eraseWebsiteData()
    }
}
