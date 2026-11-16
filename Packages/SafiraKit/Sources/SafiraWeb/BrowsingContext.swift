// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraSession

/// What a window shows tabs from: a Profile's owner for the Main window, or a Private window's own context. The two
/// are different types on purpose; they share only what a window needs to draw and drive Tabs.
@MainActor
public protocol BrowsingContext: AnyObject {
    var session: ProfileSession { get }
    var web: ProfileWebContext { get }
}

extension ProfileContext: BrowsingContext {}

extension BrowsingContext {
    /// Leaves the site's cookie prompts for the user to answer, and reloads the shown Tab so its prompt comes back. A
    /// Profile saves the exception with its settings; a Private window keeps it in memory, for the window's life.
    public func allowCookiePrompts(onSite site: String) {
        var settings = web.webContentSettings
        settings.cookiePrompts.addException(forHost: site)
        web.webContentSettings = settings
        session.setWebContentSettings(settings)
        session.reload()
    }
}
