// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Foundation
import SafiraCore
import SafiraSession

/// The words the downloads button and panel show, apart from the views so that tests read them.
public enum DownloadText {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(1, seconds.rounded(.up)))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
    }

    /// The state line under a download's name.
    public static func status(of download: DownloadRecord, timeRemaining: TimeInterval?, failure: DownloadFailure?,
                              now: Date) -> String {
        let received = size(download.receivedBytes)
        switch download.state {
        case .active:
            guard let total = download.totalBytes else { return received }
            if let timeRemaining {
                return String(localized: "\(received) of \(size(total)), \(duration(timeRemaining)) left",
                              table: "DownloadsUI", bundle: .module, comment: "Downloads panel: a running download")
            }
            return String(localized: "\(received) of \(size(total))", table: "DownloadsUI", bundle: .module,
                          comment: "Downloads panel: a running download whose time left is not known yet")
        case .paused:
            if let total = download.totalBytes {
                return String(localized: "Paused, \(received) of \(size(total))", table: "DownloadsUI", bundle: .module,
                              comment: "Downloads panel")
            }
            return String(localized: "Paused, \(received)", table: "DownloadsUI", bundle: .module, comment: "Downloads panel")
        case .completed:
            let when = download.finishedAt.map {
                RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: now)
            } ?? ""
            return String(localized: "\(received), \(when)", table: "DownloadsUI", bundle: .module,
                          comment: "Downloads panel: a finished download, its size and when it finished (“5 minutes ago”)")
        case .cancelled:
            return String(localized: "Cancelled", table: "DownloadsUI", bundle: .module, comment: "Downloads panel")
        case .failed:
            switch failure {
            case .error(let reason):
                return String(localized: "Failed: \(reason)", table: "DownloadsUI", bundle: .module,
                              comment: "Downloads panel: the engine's own description of the error")
            case .quit:
                return String(localized: "Failed: Safira quit before the end", table: "DownloadsUI", bundle: .module,
                              comment: "Downloads panel")
            case .unknown, nil:
                return String(localized: "Failed: the transfer broke off", table: "DownloadsUI", bundle: .module,
                              comment: "Downloads panel")
            }
        }
    }

    /// What VoiceOver reads after "Downloads": "2 in progress, 45 %", "1 failed".
    public static func value(of indicator: DownloadsIndicator) -> String {
        var parts: [String] = []
        if indicator.runningCount > 0 {
            parts.append(String(localized: "\(indicator.runningCount) in progress", table: "DownloadsUI", bundle: .module,
                                comment: "Downloads button, VoiceOver: how many downloads run"))
            if let percent = indicator.percent {
                parts.append(String(localized: "\(percent) %", table: "DownloadsUI", bundle: .module,
                                    comment: "Downloads button, VoiceOver: the combined progress"))
            }
        }
        if indicator.needsAttention {
            parts.append(String(localized: "a download failed", table: "DownloadsUI", bundle: .module,
                                comment: "Downloads button, VoiceOver"))
        }
        if parts.isEmpty {
            return String(localized: "none in progress", table: "DownloadsUI", bundle: .module,
                          comment: "Downloads button, VoiceOver: nothing runs")
        }
        return parts.joined(separator: ", ")
    }
}
