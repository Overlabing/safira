// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Darwin
import Foundation
import SafiraCore
import SafiraSession
import WebKit

/// The download delegate of one Profile: it takes the downloads its pages start, chooses where they are saved, and
/// reports to the Profile's `ProfileDownloads`. A page's download belongs to the Profile, not to the page: this object
/// outlives the page and holds the transfer.
@MainActor
final class DownloadController: NSObject, WKDownloadDelegate, DownloadEngine {
    let downloads: ProfileDownloads
    /// Where files are saved. The user's Downloads folder unless a test chooses another.
    var directory: URL
    /// Where files are saved when the user declines access to `directory`: a real folder inside the app's own
    /// container, which needs no consent.
    var fallbackDirectory: URL
    /// The app's container: the fallback folder must stay inside it once symbolic links are resolved.
    var container: URL
    /// Whether Safira may use a folder. Asking can take as long as the user takes to answer macOS's prompt, so it runs
    /// off the main actor: a closure that is not isolated to it.
    var access: @Sendable (URL) async -> Bool
    private var accessCheck: Task<Bool, Never>?
    /// A web view of the Profile that can start or resume a download when no page is there to do it.
    private let makeHost: @MainActor () -> WKWebView
    private var host: WKWebView?
    private var transfers: [ObjectIdentifier: Transfer] = [:]

    init(downloads: ProfileDownloads, directory: URL = DownloadController.userDownloadsDirectory(),
         fallbackDirectory: URL = FallbackFolder.defaultFolder(),
         container: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
         access: @escaping @Sendable (URL) async -> Bool = { await FolderAccess.isAllowed($0) },
         makeHost: @escaping @MainActor () -> WKWebView) {
        self.downloads = downloads
        self.directory = directory
        self.fallbackDirectory = fallbackDirectory
        self.container = container
        self.access = access
        self.makeHost = makeHost
    }

    /// The real Downloads folder. A sandboxed app's home directory is its container, so the folder is found through
    /// the user database; the `files.downloads.read-write` entitlement is what opens it.
    static func userDownloadsDirectory() -> URL {
        if let entry = getpwuid(getuid()), let home = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
                .appending(path: "Downloads", directoryHint: .isDirectory)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    /// Settles where files are saved, asking macOS for access to the folder when it has not been asked yet. Suspends
    /// while the prompt is open without holding the main thread, so pages and windows keep running. A refusal is
    /// re-asked at the next download, which costs nothing and notices the user allowing it in System Settings.
    /// - Returns: The folder to save in, or nil when access was declined and the fallback folder cannot be used either.
    @discardableResult
    func resolveDirectory() async -> URL? {
        let folder = directory
        let access = self.access
        let check = accessCheck ?? Task { await access(folder) }
        accessCheck = check
        let allowed = await check.value
        accessCheck = nil
        downloads.setSavesInAppFolder(!allowed)
        if allowed { return folder }
        return FallbackFolder.prepare(fallbackDirectory, declined: folder, container: container)
    }

    /// The folder a download's file is saved in: the one recorded when its destination was chosen, the Profile's own
    /// for a download that predates the record.
    func folder(for record: DownloadRecord) -> URL {
        record.folder ?? directory
    }

    /// Whether a running download of another record writes to this file.
    private func isInUse(_ file: URL, byAnotherThan id: DownloadID) -> Bool {
        transfers.values.contains { $0.id != id && $0.partial?.standardizedFileURL == file.standardizedFileURL }
    }

    /// A download a page of this Profile has just started.
    func adopt(_ download: WKDownload) {
        let url = download.originalRequest?.url ?? URL(string: "about:blank")!
        let id = downloads.begin(from: url, fileName: url.lastPathComponent.isEmpty ? url.host() ?? "download" : url.lastPathComponent)
        track(download, as: id)
    }

    func restart(_ record: DownloadRecord) {
        let folder = folder(for: record)
        let partial = partialFile(named: record.fileName, in: folder)
        // A transfer started over cannot reuse the broken one's file; one resumed carries on in it.
        if record.resumeData == nil, !isInUse(partial, byAnotherThan: record.id) {
            try? FileManager.default.removeItem(at: partial)
        }
        let host = self.host ?? makeHost()
        self.host = host
        // The delegate is set in the completion handler itself, never after an `await`: WebKit asks it for a
        // destination, or reports a short transfer's end, in the messages that follow, and a download with no delegate
        // by then is cancelled or ends unheard, leaving the retried download listed as running forever.
        let started: @MainActor @Sendable (WKDownload) -> Void = { [weak self] download in
            guard let self else {
                download.cancel(nil)
                return
            }
            let transfer = track(download, as: record.id)
            // WebKit resumes into the file it was writing and does not ask for a destination again.
            if record.resumeData != nil {
                transfer.finalName = record.fileName
                transfer.partial = partial
                transfer.folder = folder
            }
        }
        if let resumeData = record.resumeData {
            host.resumeDownload(fromResumeData: resumeData, completionHandler: started)
        } else {
            host.startDownload(using: URLRequest(url: record.sourceURL), completionHandler: started)
        }
    }

    func discardPartialFile(of record: DownloadRecord) {
        let partial = partialFile(named: record.fileName, in: folder(for: record))
        guard !isInUse(partial, byAnotherThan: record.id) else { return }
        try? FileManager.default.removeItem(at: partial)
    }

    /// Stops every transfer and deletes the unfinished files, for a Profile that goes away.
    func cancelAll() async {
        await downloads.cancelAll()
    }

    @discardableResult
    private func track(_ download: WKDownload, as id: DownloadID) -> Transfer {
        download.delegate = self
        let transfer = Transfer(id: id, download: download, downloads: downloads)
        // A cancelled download reports nothing more, so the transfer is let go here: holding it would keep the
        // Profile's data store in use.
        transfer.didCancel = { [weak self] in self?.transfers.removeValue(forKey: ObjectIdentifier(download)) }
        transfers[ObjectIdentifier(download)] = transfer
        downloads.attach(transfer, to: id)
        return transfer
    }

    /// Bytes arrive in `name.part` and the file takes its name when the download is complete, so that a download that
    /// stopped halfway never looks like a finished file.
    private func partialFile(named name: String, in folder: URL) -> URL {
        folder.appending(path: name + Self.partialSuffix)
    }

    private static let partialSuffix = ".part"

    private func exists(_ name: String, in folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: name).path(percentEncoded: false))
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String) async -> URL? {
        guard transfers[ObjectIdentifier(download)] != nil else { return nil }
        guard let folder = await resolveDirectory() else { return nil }
        // The download may have been cancelled while the prompt was open.
        guard let transfer = transfers[ObjectIdentifier(download)] else { return nil }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let reserved = Set(transfers.values.compactMap(\.finalName))
        let name = DownloadFileName.unique(DownloadFileName.sanitized(suggestedFilename)) { candidate in
            reserved.contains(candidate) || exists(candidate, in: folder) || exists(candidate + Self.partialSuffix, in: folder)
        }
        transfer.finalName = name
        transfer.folder = folder
        transfer.partial = partialFile(named: name, in: folder)
        downloads.named(transfer.id, fileName: name, folder: folder)
        return transfer.partial
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let transfer = transfers.removeValue(forKey: ObjectIdentifier(download)) else { return }
        guard let partial = transfer.partial, let wanted = transfer.finalName else {
            downloads.fail(transfer.id, resumeData: nil)
            return
        }
        // Something else may have taken the name while the bytes came in.
        let folder = transfer.folder ?? directory
        let name = DownloadFileName.unique(wanted) { exists($0, in: folder) }
        let file = folder.appending(path: name)
        do {
            try FileManager.default.moveItem(at: partial, to: file)
        } catch {
            downloads.fail(transfer.id, resumeData: nil)
            return
        }
        let bookmark = try? file.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false)))?[.size] as? Int64
        downloads.complete(transfer.id, fileName: name, fileBookmark: bookmark, size: size)
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        guard let transfer = transfers.removeValue(forKey: ObjectIdentifier(download)) else { return }
        downloads.fail(transfer.id, resumeData: resumeData)
    }
}

/// One running `WKDownload`, with the observation that feeds its progress to the manager.
@MainActor
private final class Transfer: DownloadTransfer {
    let id: DownloadID
    let download: WKDownload
    /// The name the file takes when the download is complete, and the file the bytes arrive in until then.
    var finalName: String?
    var partial: URL?
    /// The folder both live in.
    var folder: URL?
    var didCancel: (() -> Void)?
    private var observations: [NSKeyValueObservation] = []

    init(id: DownloadID, download: WKDownload, downloads: ProfileDownloads) {
        self.id = id
        self.download = download
        let progress = download.progress
        let report: @Sendable (Progress, Any) -> Void = { progress, _ in
            let received = progress.completedUnitCount
            let total = progress.totalUnitCount
            Task { @MainActor in downloads.progress(id, received: received, total: total > 0 ? total : nil) }
        }
        observations = [
            progress.observe(\.completedUnitCount) { progress, _ in report(progress, 0) },
            progress.observe(\.totalUnitCount) { progress, _ in report(progress, 0) },
        ]
    }

    func cancel() async -> Data? {
        let resumeData = await download.cancel()
        didCancel?()
        return resumeData
    }
}
