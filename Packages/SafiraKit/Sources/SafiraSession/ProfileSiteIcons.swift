// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import CoreGraphics
import Foundation
import Observation
import SiteIcons

/// The `<link>` elements of a page that finished loading, as Safira's own script read them in its content world.
public struct PageIconLinks: Sendable, Equatable {
    /// The address of the page that loaded.
    public var page: URL
    /// The document base URL: the first `<base href>`, else the page's address.
    public var base: URL
    /// The attributes of each `<link>`, names lowercased.
    public var tags: [[String: String]]

    public init(page: URL, base: URL, tags: [[String: String]]) {
        self.page = page
        self.base = base
        self.tags = tags
    }
}

/// What fetching an icon or a manifest gave.
public enum SiteResourceResponse: Sendable, Equatable {
    /// A successful answer, its body within the limit asked for, with its `Cache-Control` header.
    case resource(Data, cacheControl: String?)
    /// The server answered, but with no body to use: an error status, or a body over the limit.
    case unusable
    /// No answer: the network failed, or the page that would fetch is gone.
    case failed
}

/// What fetches a site's icons and manifest: the loaded page itself, through its Profile's data store. Nothing else
/// fetches an icon, so no request goes to a site whose page the user has not loaded.
@MainActor
public protocol SiteResourceFetcher: AnyObject {
    func fetchSiteResource(_ url: URL, byteLimit: Int) async -> SiteResourceResponse
}

/// The site icons of one Profile, keyed by page origin (`https://host[:port]`): decoded ones in memory, and the rest
/// on disk in the Profile's own folder, so no Profile ever reads another's. Looking an icon up only reads the cache; the
/// one thing that fetches is a loaded page reporting its links (`pageLoaded`). Only HTTPS pages have icons, since the
/// kit keeps HTTPS icon addresses only; any other page shows its letter tile.
@MainActor
@Observable
public final class ProfileSiteIcons {
    /// Safira's bounds on an icon's `Cache-Control`: at least a day, so a `no-cache` icon is not fetched again at every
    /// visit; at most 30 days, so a site's new icon shows within a month; a week when the server says nothing.
    public nonisolated static let lifetime = IconLifetime(minimum: 86_400, maximum: 30 * 86_400, fallback: 7 * 86_400)
    /// How long a site that answered with no usable icon is not asked again.
    public nonisolated static let negativeLifetime: TimeInterval = 86_400
    nonisolated static let iconByteLimit = 1_048_576
    nonisolated static let manifestByteLimit = 262_144
    nonisolated static let candidateLimit = 8
    /// The 32 pt tile at 2x.
    nonisolated static let pixelSize = 64

    private var memory = HotIconCache(byteLimit: 8 * 1_048_576)
    /// Nil for a cache kept in memory only (a Private window, or a Profile with no folder).
    @ObservationIgnored private let disk: SiteIconCache?
    /// The origins whose answer holds until the date: no fetch before it.
    @ObservationIgnored private var settledUntil: [String: Date] = [:]
    /// The origins already looked up on disk since launch or the last clearing.
    @ObservationIgnored private var lookedUp: Set<String> = []
    @ObservationIgnored private var refreshing: Set<String> = []
    /// Raised by clearing, so that work started before it writes nothing after it.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var work: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private let now: @Sendable () -> Date
    /// Called when an icon could not be written to disk; it stays in memory.
    @ObservationIgnored public var onError: (@MainActor (any Error) -> Void)?

    /// - Parameter directory: the folder of the Profile's icons; nil keeps them in memory only.
    public init(directory: URL?, now: @escaping @Sendable () -> Date = { Date() }) {
        disk = directory.map {
            SiteIconCache(directory: $0, negativeLifetime: Self.negativeLifetime,
                          legacyLifetime: Self.lifetime.fallback, now: now)
        }
        self.now = now
    }

    /// The folder holding this Profile's icons; nil when they are kept in memory only.
    public var directory: URL? { disk?.directory }

    /// The cache key of a page: its origin, `https://host` or `https://host:port`; nil for a page that is not HTTPS.
    public nonisolated static func key(for address: URL?) -> String? {
        guard let address, address.scheme?.lowercased() == "https",
              let host = address.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if let port = address.port, port != 443 { return "https://\(host):\(port)" }
        return "https://\(host)"
    }

    /// The icon cached for the site of `address`, in memory, else nil while the disk is read; the view showing it is
    /// updated when the read finds one. Never fetches.
    public func icon(for address: URL?) -> CGImage? {
        guard let key = Self.key(for: address) else { return nil }
        if let image = memory.images[key] { return image }
        if lookedUp.insert(key).inserted {
            let generation = generation
            track { [weak self] in
                guard let self, case .icon(let image, _) = await readDisk(key), generation == self.generation,
                      memory.images[key] == nil else { return }
                memory.insert(image, for: key)
            }
        }
        return nil
    }

    /// A page of this Profile finished loading: when its site's cached answer is missing or expired, its icon is found
    /// from `links` and fetched through `fetcher`, the page itself.
    public func pageLoaded(_ links: PageIconLinks, fetcher: any SiteResourceFetcher) {
        guard let key = Self.key(for: links.page), let host = links.page.host(percentEncoded: false)?.lowercased(),
              settledUntil[key].map({ $0 <= now() }) ?? true, refreshing.insert(key).inserted else { return }
        let origin = links.page.port.map { $0 == 443 ? host : "\(host):\($0)" } ?? host
        let generation = generation
        track { [weak self] in
            await self?.refresh(key, origin: origin, host: host, links: links, fetcher: fetcher, generation: generation)
            self?.refreshing.remove(key)
        }
    }

    /// Removes the icons fetched or renewed at or after `start`, in memory and on disk, as Clear history and website
    /// data does for the Profile.
    public func clear(since start: Date) async throws {
        generation += 1
        memory = HotIconCache(byteLimit: memory.byteLimit)
        settledUntil = [:]
        lookedUp = []
        guard let directory = disk?.directory else { return }
        try await Task.detached(priority: .userInitiated) {
            try Self.removeFiles(in: directory, modifiedSince: start)
        }.value
    }

    /// Returns once every lookup and fetch started so far has finished.
    public func settled() async {
        while let task = work.values.first {
            await task.value
        }
    }

    // MARK: Private

    private func refresh(_ key: String, origin: String, host: String, links: PageIconLinks,
                         fetcher: any SiteResourceFetcher, generation: Int) async {
        let existing = await readDisk(key)
        guard generation == self.generation else { return }
        switch existing {
        case .icon(let image, let isExpired):
            if memory.images[key] == nil { memory.insert(image, for: key) }
            guard isExpired else {
                settledUntil[key] = disk?.expiry(key) ?? now().addingTimeInterval(Self.lifetime.minimum)
                return
            }
        case .missing:
            settledUntil[key] = now().addingTimeInterval(Self.negativeLifetime)
            return
        case nil:
            break
        }
        // A subdomain of the page's site may serve its icons; the registrable domain is not known without a suffix list.
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let pageLinks = IconDiscovery.links(fromTags: links.tags, base: links.base, site: site)
        var manifestIcons: [URL] = []
        if let manifest = pageLinks.manifest,
           case .resource(let data, _) = await fetcher.fetchSiteResource(manifest, byteLimit: Self.manifestByteLimit) {
            manifestIcons = IconDiscovery.manifestIcons(data, manifest: manifest, site: site)
        }
        var answered = false
        let candidates = IconDiscovery.candidates(pageLinks, manifestIcons: manifestIcons, origin: origin,
                                                  limit: Self.candidateLimit)
        for candidate in candidates {
            guard generation == self.generation else { return }
            let data: Data
            var cacheControl: String?
            if let inline = DataURL(candidate.url, limit: Self.iconByteLimit) {
                data = inline.data
            } else {
                switch await fetcher.fetchSiteResource(candidate.url, byteLimit: Self.iconByteLimit) {
                case .resource(let body, let header):
                    data = body
                    cacheControl = header
                case .unusable:
                    answered = true
                    continue
                case .failed:
                    continue
                }
            }
            answered = true
            guard let image = await Self.decode(data, maskColor: candidate.maskColor) else { continue }
            guard generation == self.generation else { return }
            let lifetime = Self.lifetime.lifetime(cacheControl: cacheControl)
            memory.insert(image, for: key)
            settledUntil[key] = now().addingTimeInterval(lifetime)
            await write { try $0.writeIcon(image, key: key, lifetime: lifetime) }
            return
        }
        guard generation == self.generation else { return }
        if case .icon = existing {
            settledUntil[key] = now().addingTimeInterval(Self.lifetime.fallback)
            await write { try $0.extend(key, lifetime: Self.lifetime.fallback) }
        } else if answered {
            settledUntil[key] = now().addingTimeInterval(Self.negativeLifetime)
            await write { try $0.writeMissing(key) }
        }
    }

    private func readDisk(_ key: String) async -> SiteIconCache.Entry? {
        guard let disk else { return nil }
        return await Task.detached(priority: .utility) { disk.read(key) }.value
    }

    private func write(_ operation: @escaping @Sendable (SiteIconCache) throws -> Void) async {
        guard let disk else { return }
        do {
            try await Task.detached(priority: .utility) { try operation(disk) }.value
        } catch {
            onError?(error)
        }
    }

    /// Only the kit's decoder reads icon bytes: it checks the format before decoding anything.
    private nonisolated static func decode(_ data: Data, maskColor: String?) async -> CGImage? {
        await Task.detached(priority: .utility) {
            SiteIconDecoder.decode(data, maxPixelSize: pixelSize, maskColor: maskColor)
        }.value
    }

    /// Every file of a key goes when one of them (its icon, expiry or marker) changed at or after `start`.
    private nonisolated static func removeFiles(in directory: URL, modifiedSince start: Date) throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path(percentEncoded: false)) else { return }
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        let recent = Set(try files.filter {
            (try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantFuture) >= start
        }.map { $0.deletingPathExtension().lastPathComponent })
        for file in files where recent.contains(file.deletingPathExtension().lastPathComponent) {
            try manager.removeItem(at: file)
        }
    }

    private func track(_ operation: @escaping @MainActor () async -> Void) {
        let id = UUID()
        // The task runs on the main actor, so it cannot finish before it is recorded.
        work[id] = Task { [weak self] in
            await operation()
            self?.work[id] = nil
        }
    }
}
