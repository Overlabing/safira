// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import GRDB
import SafiraCore

extension ProfileDatabase {
    /// Every site this Profile zooms, with its zoom.
    public func siteZooms() throws -> [ZoomSite: PageZoom] {
        try queue.read { db in
            var zooms: [ZoomSite: PageZoom] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT host, factor FROM site_zoom") {
                guard let site = ZoomSite(host: row["host"]) else { continue }
                zooms[site] = PageZoom(factor: row["factor"])
            }
            return zooms
        }
    }

    /// Remembers the site's zoom; 100% forgets it.
    public func save(_ zoom: PageZoom, for site: ZoomSite) throws {
        try queue.write { db in
            if zoom.isActualSize {
                try db.execute(sql: "DELETE FROM site_zoom WHERE host = ?", arguments: [site.host])
            } else {
                try db.execute(sql: "INSERT OR REPLACE INTO site_zoom (host, factor) VALUES (?, ?)",
                               arguments: [site.host, zoom.factor])
            }
        }
    }
}
