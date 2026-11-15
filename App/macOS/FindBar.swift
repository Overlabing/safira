// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import ColorCore
import DesignKit
import Observation
import SafiraSession
import SwiftUI
import WebKit

/// The window asks the find bar's field for the keyboard focus through it, as the Tab list does with `ColumnFocus`.
@MainActor
@Observable
final class FindBarFocus {
    private(set) var request = 0

    func focusField() {
        request += 1
    }
}

/// The find bar over the top right of the page: the text, where the highlighted match is among the page's matches,
/// previous and next, and close. Return finds the next match, Shift-Return the previous one, Escape closes the bar.
struct FindBar: View {
    let find: () -> PageFind
    let focus: FindBarFocus
    let theme: () -> Theme
    /// Escape or the close button: the window hides the bar and gives the keyboard back to the page.
    let close: () -> Void
    @State private var text = ""
    @FocusState private var fieldHasFocus: Bool
    @Environment(\.designTokens) private var tokens

    var body: some View {
        let find = find()
        if find.isShown {
            WithColorRoles { roles in
                HStack(spacing: tokens.spacing.pillTileToText) {
                    Image(systemName: "magnifyingglass")
                        .font(tokens.type.accessory.font)
                        .foregroundStyle(roles.secondaryText)
                        .accessibilityHidden(true)
                    TextField(String(localized: "Find in Page", comment: "Find bar: placeholder of the field"), text: $text)
                        .textFieldStyle(.plain)
                        .frame(width: 180)
                        .focused($fieldHasFocus)
                        .onSubmit {
                            let backwards = NSEvent.modifierFlags.contains(.shift)
                            Task { backwards ? await find.previous() : await find.next() }
                        }
                        .onExitCommand(perform: close)
                        .accessibilityLabel(Text("Find in Page"))
                    Text(Self.describe(find.result))
                        .role(tokens.type.count)
                        .monospacedDigit()
                        .foregroundStyle(roles.secondaryText)
                        .lineLimit(1)
                        .accessibilityHidden(find.result == .empty)
                    IconButton(String(localized: "Previous Match", comment: "Find bar: button"), systemImage: "chevron.up") {
                        Task { await find.previous() }
                    }
                    .disabled(find.result == .empty || find.result == .notFound)
                    IconButton(String(localized: "Next Match", comment: "Find bar: button"), systemImage: "chevron.down") {
                        Task { await find.next() }
                    }
                    .disabled(find.result == .empty || find.result == .notFound)
                    IconButton(String(localized: "Close Find Bar", comment: "Find bar: button"), systemImage: "xmark",
                               action: close)
                }
                .padding(.leading, tokens.spacing.rowInsetHorizontal)
                .frame(height: tokens.size.sidebarField)
                .surface(.glass(tint: 0), in: Capsule(style: .continuous))
            }
            .theme(theme())
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Find in Page"))
            .onChange(of: text) { _, text in
                guard text != find.text else { return }
                Task { await find.search(text) }
            }
            .onChange(of: focus.request, initial: true) {
                text = find.text
                fieldHasFocus = true
            }
        }
    }

    /// "2 of 5", "No matches", or nothing before a search or for a match the page's text does not show.
    static func describe(_ result: PageFind.Result) -> String {
        switch result {
        case .empty, .uncounted: ""
        case .notFound: String(localized: "No matches", comment: "Find bar: nothing in the page matches the text")
        case .match(let current, let count):
            String(localized: "\(current) of \(count)", comment: "Find bar: the highlighted match's place among the page's matches")
        }
    }
}

/// The find bar's hosting view takes its size from the bar and lets clicks beside it through to the page.
final class FindBarHostingView: NSHostingView<FindBar> {
    required init(rootView: FindBar) {
        super.init(rootView: rootView)
        sizingOptions = [.intrinsicContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

/// ⌘P: WebKit's print operation for the page, as a sheet of the window.
@MainActor
enum PagePrinter {
    static func print(_ webView: WKWebView, in window: NSWindow) {
        let operation = webView.printOperation(with: NSPrintInfo.shared)
        // WebKit's print view has no size of its own; without one the operation prints blank pages.
        operation.view?.frame = webView.bounds
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
