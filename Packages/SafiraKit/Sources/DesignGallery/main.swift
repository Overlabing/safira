// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import DesignKit
import SwiftUI
import ThemeStandIn

// Renders every direction × screen × Theme × appearance into PNGs, then one overview per direction.
// Usage: DesignGallery <output directory>
// Liquid Glass composites only in a window on screen, so each mock is shown in its own window, which is captured by
// window id (never the screen) and closed.

struct Shot {
    let tokens: DesignTokens
    let screen: MockScreen
    let theme: Theme
    let isDark: Bool
    var accessibility = false

    var file: String {
        let base = accessibility ? "a11y-contrast-transparency" : screen.rawValue
        return "\(Self.slug(tokens))/\(base)-\(theme.id)-\(isDark ? "dark" : "light").png"
    }

    static func slug(_ tokens: DesignTokens) -> String { tokens.name.lowercased().replacingOccurrences(of: " ", with: "-") }
}

@MainActor
func capture(_ shot: Shot, into directory: URL) async throws {
    let root = MainWindow(screen: shot.screen)
        .design(shot.tokens, theme: shot.theme)
        .accessibilityOverrides(increaseContrast: shot.accessibility, reduceTransparency: shot.accessibility)
        // The window is shown without activating the app (no focus taken), so draw its controls as in a key window.
        .environment(\.appearsActive, true)
        .environment(\.controlActiveState, .key)
    let window = NSWindow(
        contentRect: CGRect(origin: CGPoint(x: 40, y: 40), size: MockLayout.window),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.appearance = NSAppearance(named: shot.isDark ? .darkAqua : .aqua)
    window.contentView = NSHostingView(rootView: root)
    window.setContentSize(MockLayout.window)
    window.orderFrontRegardless()
    try await Task.sleep(for: .milliseconds(1200))

    let url = directory.appending(path: shot.file)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let process = Process()
    process.executableURL = URL(filePath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l\(window.windowNumber)", url.path]
    try process.run()
    process.waitUntilExit()
    window.orderOut(nil)
    window.close()
    guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
        throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
    }
    print("OK: \(shot.file)")
}

/// Main window, light and dark side by side, one row per Theme.
func overview(_ tokens: DesignTokens, directory: URL) throws {
    let gap = 48
    let titleHeight = 120
    let images = Sample.themes.map { theme in
        [false, true].map { isDark in
            let file = Shot(tokens: tokens, screen: .main, theme: theme, isDark: isDark).file
            return NSImage(contentsOf: directory.appending(path: file))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }
    guard let first = images.first?.first ?? nil else { throw CocoaError(.fileReadNoSuchFile) }
    let cell = (width: first.width, height: first.height)
    let width = cell.width * 2 + gap * 3
    let height = titleHeight + cell.height * images.count + gap * (images.count + 1)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else { throw CocoaError(.fileWriteUnknown) }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    NSColor(white: 0.5, alpha: 1).setFill()
    CGRect(x: 0, y: 0, width: width, height: height).fill()
    let title = "\(tokens.name)  ·  light | dark  ·  rows: \(Sample.themes.map(\.id).joined(separator: ", "))"
    (title as NSString).draw(
        at: CGPoint(x: gap, y: height - titleHeight + 24),
        withAttributes: [.font: NSFont.systemFont(ofSize: 56, weight: .semibold), .foregroundColor: NSColor.white])
    for (row, pair) in images.enumerated() {
        for (column, image) in pair.enumerated() {
            guard let image else { continue }
            let x = gap + column * (cell.width + gap)
            let y = height - titleHeight - (row + 1) * (cell.height + gap)
            context.cgContext.draw(image, in: CGRect(x: x, y: y, width: cell.width, height: cell.height))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    let url = directory.appending(path: "\(Shot.slug(tokens))-overview.png")
    try rep.representation(using: .png, properties: [:])?.write(to: url)
    print("OK: \(url.lastPathComponent)")
}

@MainActor
func renderAll(into directory: URL) async {
    do {
        for tokens in DesignTokens.all where only == nil || Shot.slug(tokens) == only {
            for theme in Sample.themes {
                for isDark in [false, true] {
                    for screen in MockScreen.allCases {
                        try await capture(Shot(tokens: tokens, screen: screen, theme: theme, isDark: isDark), into: directory)
                    }
                }
            }
            try await capture(
                Shot(tokens: tokens, screen: .main, theme: Sample.themes[0], isDark: true, accessibility: true), into: directory)
            try await capture(
                Shot(tokens: tokens, screen: .main, theme: Sample.themes[1], isDark: false, accessibility: true), into: directory)
            try overview(tokens, directory: directory)
        }
        exit(0)
    } catch {
        print("FAILED: \(error)")
        exit(1)
    }
}

guard (2...3).contains(CommandLine.arguments.count) else {
    print("usage: DesignGallery <output directory> [direction slug]")
    exit(2)
}
let only = CommandLine.arguments.count == 3 ? CommandLine.arguments[2] : nil
let output = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { await renderAll(into: output) }
app.run()
