// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import DesignKit
import SwiftUI
import ThemeStandIn

// Browser-specific views composed from DesignKit, with sample data: what the Main window, the Command bar, a sheet and
// a banner would look like in each direction. Mock only; the real screens come with the layout work.

enum Sample {
    static let themes = [
        Theme(id: "indigo-blue", primary: .indigo, secondary: .blue),
        Theme(id: "teal-green", primary: .teal, secondary: .green),
    ]

    struct Row: Identifiable {
        let id = UUID()
        let title: String
        let symbol: String
        let color: Color
        var indent = 0
        var isSelected = false
        var isHovered = false
        var isPlaying = false
    }

    static let pinned = [
        Row(title: "Inbox", symbol: "envelope.fill", color: .blue),
        Row(title: "Calendar", symbol: "calendar", color: .red),
        Row(title: "Tickets", symbol: "checklist", color: .purple),
    ]
    static let folderChildren = [
        Row(title: "Design notes", symbol: "doc.text.fill", color: .orange, indent: 1),
        Row(title: "Swift Forums", symbol: "bubble.left.and.bubble.right.fill", color: .teal, indent: 1),
    ]
    static let tabs = [
        Row(title: "Swift Testing | Apple Developer", symbol: "hammer.fill", color: .orange, isSelected: true),
        Row(title: "Lo-fi beats to code to", symbol: "play.rectangle.fill", color: .red, isPlaying: true),
        Row(title: "WebKit Features in Safari", symbol: "safari.fill", color: .blue, isHovered: true),
        Row(title: "Weather in Lyon", symbol: "cloud.sun.fill", color: .cyan),
    ]
    static let spaces = [
        SwitcherItem(id: "studio", label: "Studio", glyph: "🎨"),
        SwitcherItem(id: "reading", label: "Reading", glyph: "📚"),
        SwitcherItem(id: "home", label: "Home", glyph: "🏠"),
    ]
    static let host = "developer.apple.com"
    static let url = "https://developer.apple.com/documentation/testing"
}

/// Window geometry of the mock, outside the token set: it belongs to the window, not to the design.
enum MockLayout {
    static let window = CGSize(width: 1280, height: 800)
    /// Room left of the sidebar's top row for the window's traffic lights.
    static let trafficLights: CGFloat = 76
    static let topRow: CGFloat = 40
}

enum MockScreen: String, CaseIterable {
    case main, commandBar = "command-bar", sheet, banner
}

/// A Tab, Pinned tab or Folder child row: a kit `ListRow` with a favicon-like tile and the audio indicator.
struct TabRow: View {
    @Environment(\.designTokens) private var tokens
    let row: Sample.Row

    var body: some View {
        ListRow(row.title, state: RowState(isSelected: row.isSelected, isHovered: row.isHovered), indent: row.indent) {
            Tile(systemImage: row.symbol, color: row.color)
        } trailing: {
            if row.isPlaying {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(localized: "Playing audio"))
            }
        }
    }
}

struct FolderRow: View {
    @Environment(\.designTokens) private var tokens
    let title: String

    var body: some View {
        ListRow(title) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
                .frame(width: tokens.size.tile, height: tokens.size.tile)
        } trailing: {
            Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }
}

struct Sidebar: View {
    @Environment(\.designTokens) private var tokens
    let pillText: String?

    var body: some View {
        let spacing = tokens.spacing
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                IconButton(String(localized: "Toggle Sidebar"), systemImage: "sidebar.left")
                Spacer()
                IconButton(String(localized: "Back"), systemImage: "arrow.left")
                IconButton(String(localized: "Forward"), systemImage: "arrow.right")
                IconButton(String(localized: "Reload"), systemImage: "arrow.clockwise")
            }
            .padding(.leading, MockLayout.trafficLights)
            .padding(.trailing, spacing.listMargin - DesignTokens.Spacing.xs)
            .frame(height: MockLayout.topRow)

            FieldPill(pillText, label: String(localized: "Address"))
                .padding(.bottom, spacing.groupGap)

            HStack(spacing: spacing.tileToText) {
                Text(verbatim: "🎨")
                Text(verbatim: "Studio").role(tokens.type.columnTitle)
                Spacer()
                Image(systemName: "ellipsis").foregroundStyle(.tertiary)
            }
            .padding(.horizontal, spacing.listMargin)
            .padding(.bottom, spacing.groupGap)
            .accessibilityAddTraits(.isHeader)

            if tokens.name != "Slim Frame" {
                SectionHeader(String(localized: "Pinned"))
            }
            ForEach(Sample.pinned) { TabRow(row: $0) }
            FolderRow(title: "Reading list")
            ForEach(Sample.folderChildren) { TabRow(row: $0) }
            ColumnDivider()
            ListRow(String(localized: "New Tab")) {
                Image(systemName: "plus")
                    .foregroundStyle(.secondary)
                    .frame(width: tokens.size.tile, height: tokens.size.tile)
            }
            .foregroundStyle(.secondary)
            ForEach(Sample.tabs) { TabRow(row: $0) }
            Spacer(minLength: 0)
            HStack(spacing: DesignTokens.Spacing.xs) {
                IconButton(String(localized: "New Space"), systemImage: "plus")
                Spacer(minLength: 0)
                GlassSwitcher(Sample.spaces, selection: "studio", label: String(localized: "Spaces"))
                Spacer(minLength: 0)
                IconButton(String(localized: "Downloads"), systemImage: "arrow.down.circle")
            }
            .padding(.horizontal, spacing.listMargin - DesignTokens.Spacing.xs)
            .padding(.bottom, spacing.listMargin - DesignTokens.Spacing.xs)
        }
        .frame(width: tokens.size.columnWidth)
        .frame(maxHeight: .infinity)
    }
}

/// A neutral page: a header bar, a title, paragraphs as soft bars and an image block.
struct PlaceholderPage: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = Color.primary.opacity(0.10)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                Circle().fill(Color.primary.opacity(0.18)).frame(width: 22, height: 22)
                ForEach([64, 48, 72, 56], id: \.self) { width in
                    Capsule().fill(ink).frame(width: CGFloat(width), height: 8)
                }
                Spacer()
                Capsule().fill(Color.primary.opacity(0.14)).frame(width: 90, height: 26)
            }
            .padding(.bottom, 28)
            Text(verbatim: "Placeholder page")
                .font(.system(size: 34, weight: .bold, design: .serif))
                .foregroundStyle(.primary.opacity(0.75))
            ForEach(Array([1.0, 0.94, 0.97, 0.6].enumerated()), id: \.offset) { _, share in
                GeometryReader { proxy in
                    Capsule().fill(ink).frame(width: proxy.size.width * share, height: 10)
                }
                .frame(height: 10)
            }
            RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)).frame(height: 220)
                .overlay { Image(systemName: "photo").font(.largeTitle).foregroundStyle(.quaternary) }
            ForEach(Array([0.98, 0.9, 0.95, 0.4].enumerated()), id: \.offset) { _, share in
                GeometryReader { proxy in
                    Capsule().fill(ink).frame(width: proxy.size.width * share, height: 10)
                }
                .frame(height: 10)
            }
            Spacer()
        }
        .padding(.horizontal, 72)
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(scheme == .dark ? Color(white: 0.12) : Color.white)
        .accessibilityHidden(true)
    }
}

struct CommandBar: View {
    @Environment(\.designTokens) private var tokens

    var body: some View {
        FloatingPanel {
            PanelField(Sample.url, isAllSelected: true)
        } rows: {
            PanelRow("Lo-fi beats to code to", action: String(localized: "Switch to Tab"), isSelected: true) {
                Tile(systemImage: "play.rectangle.fill", color: .red)
            }
            PanelRow("Weather in Lyon", action: String(localized: "Switch to Tab")) {
                Tile(systemImage: "cloud.sun.fill", color: .cyan)
            }
            PanelRow("Swift Testing", detail: "developer.apple.com") {
                Tile(systemImage: "hammer.fill", color: .orange)
            }
            PanelRow("Applying Liquid Glass to custom views", detail: "developer.apple.com") {
                Tile(systemImage: "drop.fill", color: .blue)
            }
            PanelRow("WebKit Features in Safari 27", detail: "webkit.org") {
                Tile(systemImage: "safari.fill", color: .blue)
            }
        }
    }
}

/// The whole Main window for one screen of the gallery.
struct MainWindow: View {
    @Environment(\.designTokens) private var tokens
    let screen: MockScreen

    var body: some View {
        let inset = tokens.spacing.pageInset
        let floatsColumn = tokens.materials.column != .none
        ZStack {
            FrameBackground()
            HStack(spacing: floatsColumn ? inset : 0) {
                Sidebar(pillText: screen == .commandBar ? nil : Sample.host)
                    .surface(tokens.materials.column, in: TokenShape(radius: tokens.radius.column))
                    .padding([.leading, .vertical], floatsColumn ? inset : 0)
                    .padding(.leading, floatsColumn || tokens.name != "Slim Frame" ? 0 : inset)
                InsetPage {
                    ZStack(alignment: .top) {
                        PlaceholderPage()
                        if screen == .commandBar {
                            Color.black.opacity(tokens.emphasis.scrim)
                            GeometryReader { proxy in
                                CommandBar()
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, proxy.size.height * tokens.size.panelTopFraction)
                            }
                        }
                        if screen == .banner {
                            Banner(
                                systemImage: "arrow.uturn.right.circle.fill",
                                message: String(localized: "This page was already open, so its Tab is shown."),
                                actionTitle: String(localized: "Open in New Tab"))
                                .padding(.top, tokens.spacing.groupGap)
                        }
                    }
                }
                .padding([.vertical, .trailing], inset)
                .padding(.leading, floatsColumn || tokens.name != "Slim Frame" ? 0 : inset)
            }
            if screen == .sheet {
                Color.black.opacity(tokens.emphasis.scrim)
                VStack {
                    ConfirmationCard(
                        systemImage: "trash",
                        title: String(localized: "Delete the Space “Reading”?"),
                        message: String(localized: "Its 6 Tabs and 2 Folders close. Logins and history stay with the Profile."),
                        confirmTitle: String(localized: "Delete Space"),
                        isDestructive: true)
                        .padding(.top, MockLayout.topRow)
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .frame(width: MockLayout.window.width, height: MockLayout.window.height)
    }
}
