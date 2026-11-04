// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Diagnostics
import Foundation
import SafiraCore
import SafiraSession
import SafiraStore

/// The one owner of a Profile's state: its website data store (through its web context), its database and its
/// session. Only `ProfileRegistry` creates one, and no API takes two of them (docs/architecture-v1.md §2.2).
@MainActor
public final class ProfileContext {
    public let id: ProfileID
    public let web: ProfileWebContext
    public let session: ProfileSession
    private let autosave: SessionAutosave

    /// Restores the Profile's Spaces, Tabs and settings from its database; only the selected Tab gets a page.
    init(id: ProfileID, database: ProfileDatabase, diagnostics: DiagnosticLogger?,
         onError: @escaping @MainActor (String, any Error) -> Void) {
        let settings: ProfileSettings
        do {
            settings = try database.settings()
        } catch {
            onError("The Profile's settings could not be read", error)
            settings = ProfileSettings()
        }
        let web = ProfileWebContext(profileID: id, webContentSettings: settings.webContent)
        web.diagnostics = diagnostics
        let session = ProfileSession(profileID: id, settings: settings) { [unowned web] in web.makePage(for: $0) }
        do {
            session.restore(try database.savedSession())
        } catch {
            onError("The saved Tabs could not be read", error)
        }
        let autosave = SessionAutosave(session: session, database: database)
        autosave.onError = { onError("The Tabs could not be saved", $0) }
        autosave.start()
        self.id = id
        self.web = web
        self.session = session
        self.autosave = autosave
    }

    /// The Profile's web content settings. A change is saved with the Profile and reaches the pages created after it.
    public var webContentSettings: WebContentSettings {
        get { session.settings.webContent }
        set {
            session.setWebContentSettings(newValue)
            web.webContentSettings = newValue
        }
    }

    /// Saves now and waits until the write has reached the database.
    public func saveNow() async {
        await autosave.saveNow()
    }

    /// Stops saving and closes every page, so that WebKit lets the data store go.
    func discard() {
        autosave.stop()
        session.closeAllTabs()
    }
}
