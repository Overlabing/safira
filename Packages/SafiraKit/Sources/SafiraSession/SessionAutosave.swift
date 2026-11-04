// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore
import SafiraStore

/// Saves a Profile's Tabs and settings into its database shortly after they change, and periodically for what changes unseen
/// (scroll positions), so that an app that is killed comes back with them. Writes run off the main actor, one after
/// the other, and are skipped when nothing changed since the last one.
@MainActor
public final class SessionAutosave {
    private let session: ProfileSession
    private let database: ProfileDatabase
    private let delay: Duration
    private let period: Duration
    private var lastSaved: SavedSession?
    private var lastSavedSettings: ProfileSettings?
    private var pending: Task<Void, Never>?
    private var writing: Task<Void, Never>?
    private var ticking: Task<Void, Never>?
    /// Called when a write fails; the next change tries again.
    public var onError: (@MainActor (any Error) -> Void)?

    /// - Parameters:
    ///   - delay: how long after a change the Tabs are saved; changes in that time are saved together.
    ///   - period: how often the Tabs are saved even when no change was observed.
    public init(session: ProfileSession, database: ProfileDatabase, delay: Duration = .seconds(1),
                period: Duration = .seconds(30)) {
        self.session = session
        self.database = database
        self.delay = delay
        self.period = period
    }

    public func start() {
        observe()
        ticking = Task { [weak self, period] in
            while !Task.isCancelled {
                try? await Task.sleep(for: period)
                self?.write()
            }
        }
    }

    public func stop() {
        ticking?.cancel()
        pending?.cancel()
        ticking = nil
        pending = nil
    }

    /// Saves now and waits until every write has reached the database.
    public func saveNow() async {
        pending?.cancel()
        pending = nil
        write()
        await writing?.value
    }

    private func observe() {
        withObservationTracking {
            session.readSavedFields()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observe()
                self?.schedule()
            }
        }
    }

    private func schedule() {
        guard pending == nil else { return }
        pending = Task { [weak self, delay] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.pending = nil
            self?.write()
        }
    }

    private func write() {
        let saved = session.savedSession()
        let settings = session.settings
        guard saved != lastSaved || settings != lastSavedSettings else { return }
        let sessionChanged = saved != lastSaved
        let settingsChanged = settings != lastSavedSettings
        lastSaved = saved
        lastSavedSettings = settings
        let previous = writing
        writing = Task { [database, weak self] in
            await previous?.value
            do {
                try await database.save(sessionChanged ? saved : nil, settingsChanged ? settings : nil)
            } catch {
                self?.lastSaved = nil
                self?.lastSavedSettings = nil
                self?.onError?(error)
            }
        }
    }
}
