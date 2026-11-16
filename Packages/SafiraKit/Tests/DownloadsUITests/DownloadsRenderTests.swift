// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import ColorCore
import ColorUI
import DesignKit
@testable import DownloadsUI
import Foundation
import SafiraCore
import SafiraSession
import SwiftUI
import Testing

/// The design renders of the downloads button and panel, drawn offscreen in a hosting view that is never in a window.
/// Every state renders something; with `SAFIRA_DOWNLOADS_RENDERS=<folder>` the PNGs are written there as well.
@MainActor
@Suite struct DownloadsRenderTests {
    nonisolated private static let start = Date(timeIntervalSince1970: 1_700_000_000)

    private final class Clock {
        var now = DownloadsRenderTests.start
    }

    enum Look: String, CaseIterable {
        case light, dark, lightContrast = "light-increased-contrast", darkContrast = "dark-increased-contrast"

        var isDark: Bool { self == .dark || self == .darkContrast }
        var increasedContrast: Bool { self == .lightContrast || self == .darkContrast }
    }

    private let theme = Palette.standard.themes[0]

    @Test func everyButtonStateRenders() throws {
        let states: [(String, DownloadsIndicator, Bool)] = [
            ("hidden", .hidden, false),
            ("finished", DownloadsIndicator(isVisible: true, finishedCount: 1), false),
            ("one running, 45 %", DownloadsIndicator(isVisible: true, runningCount: 1, fraction: 0.45), false),
            ("one running, size unknown", DownloadsIndicator(isVisible: true, runningCount: 1), false),
            ("three running, 70 %", DownloadsIndicator(isVisible: true, runningCount: 3, fraction: 0.7), false),
            ("finished, bounce peak", DownloadsIndicator(isVisible: true, finishedCount: 1), true),
            ("failed", DownloadsIndicator(isVisible: true, needsAttention: true), false),
        ]
        for look in Look.allCases {
            let sheet = HStack(alignment: .top, spacing: DesignTokens.Spacing.l) {
                ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                    VStack(spacing: DesignTokens.Spacing.s) {
                        FooterSample {
                            if state.1.isVisible {
                                DownloadsButton(indicator: state.1, isBouncing: state.2) {}
                            }
                        }
                        Text(verbatim: state.0).font(.caption).frame(width: 150).multilineTextAlignment(.center)
                    }
                }
            }
            .padding(DesignTokens.Spacing.xl)
            .background(.background)
            try render(sheet, look: look, name: "button-\(look.rawValue)")
        }
    }

    @Test func everyPanelStateRenders() async throws {
        let folder = DownloadsFolder(url: FileManager.default.temporaryDirectory.appending(path: "Downloads"), isAppFolder: false)
        for (name, downloads, folder) in [("empty", ProfileDownloads(), folder),
                                          ("running", try running(), folder),
                                          ("mixed", try await mixed(), folder),
                                          ("app-folder", try await mixed(),
                                           DownloadsFolder(url: FileManager.default.temporaryDirectory.appending(path: "Downloads"), isAppFolder: true))] {
            for look in Look.allCases {
                let panel = DownloadsPanel(downloads: downloads, folder: folder, now: { Self.start.addingTimeInterval(400) })
                    .surface(.glass(tint: 0), in: RoundedRectangle(cornerRadius: DesignTokens.standard.radius.layer))
                    .padding(DesignTokens.Spacing.xl)
                    .background { WindowBackground() }
                try render(panel, look: look, name: "panel-\(name)-\(look.rawValue)")
            }
        }
    }

    // MARK: Samples

    private func running() throws -> ProfileDownloads {
        let clock = Clock()
        let downloads = ProfileDownloads(now: { clock.now })
        let movie = downloads.begin(from: URL(string: "https://files.example/holiday.mov")!, fileName: "holiday.mov")
        let archive = downloads.begin(from: URL(string: "https://files.example/archive.zip")!, fileName: "archive.zip")
        downloads.progress(movie, received: 0, total: 840_000_000)
        downloads.progress(archive, received: 0, total: nil)
        clock.now = clock.now.addingTimeInterval(60)
        downloads.progress(movie, received: 380_000_000, total: 840_000_000)
        downloads.progress(archive, received: 12_400_000, total: nil)
        return downloads
    }

    private func mixed() async throws -> ProfileDownloads {
        let clock = Clock()
        let downloads = ProfileDownloads(now: { clock.now })
        let folder = FileManager.default.temporaryDirectory.appending(path: "safira-renders", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func finished(_ name: String, size: Int64) throws {
            let file = folder.appending(path: name)
            try Data("x".utf8).write(to: file)
            let id = downloads.begin(from: URL(string: "https://files.example/\(name)")!, fileName: name)
            downloads.complete(id, fileName: name, fileBookmark: try file.bookmarkData(), size: size)
        }
        try finished("report.pdf", size: 2_400_000)
        let failed = downloads.begin(from: URL(string: "https://files.example/dataset.csv")!, fileName: "dataset.csv")
        downloads.progress(failed, received: 3_000_000, total: 9_000_000)
        downloads.fail(failed, resumeData: nil, reason: "The network connection was lost.")
        let cancelled = downloads.begin(from: URL(string: "https://files.example/old.dmg")!, fileName: "old.dmg")
        await downloads.cancel(cancelled)
        clock.now = clock.now.addingTimeInterval(120)
        try finished("photo.jpg", size: 860_000)
        let paused = downloads.begin(from: URL(string: "https://files.example/podcast.mp3")!, fileName: "podcast.mp3")
        downloads.progress(paused, received: 21_000_000, total: 64_000_000)
        await downloads.pause(paused)
        let running = downloads.begin(from: URL(string: "https://files.example/setup.pkg")!, fileName: "setup.pkg")
        downloads.progress(running, received: 4_000_000, total: 50_000_000)
        clock.now = clock.now.addingTimeInterval(20)
        downloads.progress(running, received: 14_000_000, total: 50_000_000)
        clock.now = Self.start.addingTimeInterval(400)
        return downloads
    }

    // MARK: Rendering

    private func render(_ view: some View, look: Look, name: String) throws {
        let themed = view
            .designTokens(.standard)
            .theme(theme)
            .environment(\.glassRendering, .material)
            .environment(\.colorScheme, look.isDark ? .dark : .light)
            .accessibilityOverrides(increaseContrast: look.increasedContrast)
            .fixedSize()
        let hosting = NSHostingView(rootView: themed)
        hosting.appearance = NSAppearance(named: look.isDark ? .darkAqua : .aqua)
        hosting.frame.size = hosting.fittingSize
        hosting.layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(hosting.bounds.width * scale),
            pixelsHigh: Int(hosting.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = hosting.bounds.size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        #expect(hosting.bounds.width > 0 && hosting.bounds.height > 0, "\(name) has no size")
        guard let directory = ProcessInfo.processInfo.environment["SAFIRA_DOWNLOADS_RENDERS"] else { return }
        let data = try #require(rep.representation(using: .png, properties: [:]))
        let url = URL(fileURLWithPath: directory, isDirectory: true).appending(path: "\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

/// The sidebar's footer, as the button sits in it: the window's gradient, the button at the leading margin, then where
/// the Space rail goes.
private struct FooterSample<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        WithColorRoles { roles in
            HStack(spacing: DesignTokens.Spacing.xs) {
                content
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(roles.tileFill).frame(width: 24, height: 24)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .frame(width: 150, height: 44)
            .background { WindowBackground() }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.standard.radius.row))
        }
    }
}
