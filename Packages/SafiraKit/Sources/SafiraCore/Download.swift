// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation

/// Identifies a download in its Profile.
public struct DownloadID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum DownloadState: String, Hashable, Sendable {
    case active
    case completed
    /// The transfer broke off: a network error, or Safira quit while it ran.
    case failed
    case cancelled
}

/// One download of one Profile, as its download manager lists it and its database keeps it.
public struct DownloadRecord: Hashable, Sendable, Identifiable {
    public let id: DownloadID
    public let sourceURL: URL
    public var fileName: String
    /// Where the finished file was saved, as a bookmark so that a file the user moved is still found. Nil until the
    /// download completes.
    public var fileBookmark: Data?
    public var state: DownloadState
    public var receivedBytes: Int64
    /// Nil when the server did not say.
    public var totalBytes: Int64?
    /// What the engine needs to continue a cancelled or failed transfer where it stopped.
    public var resumeData: Data?
    public let startedAt: Date
    public var finishedAt: Date?

    public init(id: DownloadID = DownloadID(), sourceURL: URL, fileName: String, fileBookmark: Data? = nil,
                state: DownloadState = .active, receivedBytes: Int64 = 0, totalBytes: Int64? = nil,
                resumeData: Data? = nil, startedAt: Date, finishedAt: Date? = nil) {
        self.id = id
        self.sourceURL = sourceURL
        self.fileName = fileName
        self.fileBookmark = fileBookmark
        self.state = state
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.resumeData = resumeData
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    /// Between 0 and 1, or nil while the size is unknown.
    public var fractionCompleted: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(receivedBytes) / Double(totalBytes)))
    }

    /// A transfer that stopped before the end can be started again: from where it stopped when the engine kept
    /// `resumeData`, from the beginning otherwise.
    public var canRetry: Bool {
        state == .cancelled || state == .failed
    }

    /// The saved file, unless the bookmark is missing or the file is gone.
    public func savedFileURL() -> URL? {
        guard let fileBookmark else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: fileBookmark, options: [.withoutUI], relativeTo: nil,
                                 bookmarkDataIsStale: &isStale),
              FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return url
    }
}

public enum DownloadPolicy {
    /// Whether a response is saved instead of shown: the engine cannot show its type, or the server marked it as an
    /// attachment, whatever its type.
    public static func savesResponse(canShowType: Bool, contentDisposition: String?) -> Bool {
        !canShowType || isAttachment(contentDisposition)
    }

    /// `Content-Disposition: attachment; filename=…`. Any other disposition type, `inline` included, shows the content.
    static func isAttachment(_ contentDisposition: String?) -> Bool {
        guard let kind = contentDisposition?.split(separator: ";", maxSplits: 1).first else { return false }
        return kind.trimmingCharacters(in: .whitespaces).lowercased() == "attachment"
    }
}

public enum DownloadFileName {
    /// A name that stays inside the downloads folder: the server and the page choose the suggested name, so a path
    /// separator, a leading dot or an empty name never reaches the file system.
    public static func sanitized(_ suggested: String) -> String {
        let cleaned = String(suggested.unicodeScalars.map { scalar -> Character in
            scalar == "/" || scalar == ":" || scalar.value < 32 ? "_" : Character(scalar)
        }).trimmingCharacters(in: .whitespaces)
        let withoutDots = String(cleaned.drop { $0 == "." })
        return withoutDots.isEmpty ? "download" : withoutDots
    }

    /// `name.ext`, or `name 2.ext`, `name 3.ext`… for the first name `isTaken` does not refuse, as Safari numbers them.
    public static func unique(_ name: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(name) else { return name }
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            if !isTaken(candidate) { return candidate }
            number += 1
        }
    }
}
