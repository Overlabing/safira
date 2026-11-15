// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import DesignKit
import SwiftUI

/// What the page area shows once a Tab's page crashed a second time (`PageCrash.crashed`): Safira no longer reloads it
/// by itself, the user does.
struct CrashedPage: View {
    var site: String?
    var reload: () -> Void

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.s) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("This page crashed")
                .font(.title2)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Reload", comment: "Crashed page"), action: reload)
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var message: String {
        site.map { String(localized: "“\($0)” stopped working twice, so Safira did not reload it again.", comment: "Crashed page; the argument is the site") }
            ?? String(localized: "The page stopped working twice, so Safira did not reload it again.", comment: "Crashed page")
    }
}

/// The page area's view for a crashed Tab, kept by the window and given the Tab's site each time it shows.
@MainActor
final class CrashedPageHost {
    private var host: NSHostingView<CrashedPage>?

    func view(site: String?, reload: @escaping () -> Void) -> NSView {
        let page = CrashedPage(site: site, reload: reload)
        if let host {
            host.rootView = page
            return host
        }
        let host = NSHostingView(rootView: page)
        self.host = host
        return host
    }
}
