// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import ColorUI
import DesignKit
import SafiraCore
import SwiftUI

/// The small shield at the end of the address field once Safira has handled the page's cookie prompt. Clicking it
/// says what happened and offers to leave the site's prompts alone.
struct CookiePromptIndicator: View {
    static let width: CGFloat = 20

    let report: CookiePromptReport
    let allow: (String) -> Void
    @State private var isShowingDetails = false
    @Environment(\.designTokens) private var tokens

    var body: some View {
        WithColorRoles { roles in
            Button { isShowingDetails.toggle() } label: {
                Image(systemName: report.outcome == .failed ? "exclamationmark.shield" : "checkmark.shield")
                    .font(tokens.type.accessory.font)
                    .foregroundStyle(roles.secondaryText)
                    .frame(width: Self.width, height: Self.width)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressedOpacityStyle())
            .help(Self.summary(of: report))
            .accessibilityLabel(Text("Cookie prompt"))
            .accessibilityValue(Text(Self.summary(of: report)))
            .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
                CookiePromptDetails(report: report) {
                    isShowingDetails = false
                    allow(report.site)
                }
            }
        }
    }

    static func summary(of report: CookiePromptReport) -> String {
        switch report.outcome {
        case .rejected, .detected:
            String(localized: "Rejected cookies on \(report.site)",
                   comment: "Cookie indicator; the argument is a site, for example example.com")
        case .hidden:
            String(localized: "Hid the cookie prompt on \(report.site)",
                   comment: "Cookie indicator: no reject button existed; the argument is a site")
        case .failed:
            String(localized: "Could not reject the cookie prompt on \(report.site)",
                   comment: "Cookie indicator; the argument is a site")
        }
    }
}

private struct CookiePromptDetails: View {
    let report: CookiePromptReport
    let allow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(CookiePromptIndicator.summary(of: report))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Allow Prompts on This Site", action: allow)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var explanation: String {
        switch report.outcome {
        case .rejected, .detected:
            String(localized: "Safira answered “reject” to the site’s prompt (\(report.platform)).",
                   comment: "Cookie popover; the argument is the name of the site's consent platform")
        case .hidden:
            String(localized: "The prompt had no way to reject, so Safira hid it. The site received no answer.",
                   comment: "Cookie popover")
        case .failed:
            String(localized: "Safira found the prompt (\(report.platform)) but could not answer it.",
                   comment: "Cookie popover; the argument is the name of the site's consent platform")
        }
    }
}
