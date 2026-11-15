// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import Observation
import SafiraCore
import SafiraStore

/// The page zoom one Profile remembers for each site. It is saved in the Profile's own database, so another Profile
/// never sees it; a Private window keeps it in memory and forgets it when it closes.
@MainActor
@Observable
public final class SiteZooms {
    public private(set) var all: [ZoomSite: PageZoom]
    @ObservationIgnored private let database: ProfileDatabase?
    @ObservationIgnored private let onError: @MainActor (String, any Error) -> Void

    /// - Parameter database: where zooms are kept; nil keeps them for this run only.
    public init(database: ProfileDatabase? = nil, onError: @escaping @MainActor (String, any Error) -> Void = { _, _ in }) {
        self.database = database
        self.onError = onError
        do {
            all = try database?.siteZooms() ?? [:]
        } catch {
            all = [:]
            onError("The remembered page zooms could not be read", error)
        }
    }

    /// The zoom of the page at `url`: the one remembered for its site, else 100%.
    public func zoom(for url: URL?) -> PageZoom {
        ZoomSite(url).flatMap { all[$0] } ?? .actualSize
    }

    /// Remembers `zoom` for the site of `url`; an address with no site is zoomed but not remembered. A zoom that could
    /// not be saved still applies for this run.
    func remember(_ zoom: PageZoom, for url: URL?) {
        guard let site = ZoomSite(url) else { return }
        do {
            try database?.save(zoom, for: site)
        } catch {
            onError("The page zoom could not be saved", error)
        }
        all[site] = zoom.isActualSize ? nil : zoom
    }
}
