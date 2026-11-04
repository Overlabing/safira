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
