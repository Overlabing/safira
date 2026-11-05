// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import SwiftUI

extension ClearRange {
    var title: String {
        switch self {
        case .lastHour: String(localized: "Last hour", comment: "Clear history and website data sheet")
        case .lastDay: String(localized: "Last day", comment: "Clear history and website data sheet")
        case .allTime: String(localized: "All time", comment: "Clear history and website data sheet")
        }
    }
}

/// Asks which range of a Profile's Browsing data to clear, and confirms by naming the Profile. Nothing is preselected,
/// so Return clears nothing until the user has chosen a range (as for the search engine, decision D10): the safer
/// default for an action with no way back.
struct ClearBrowsingDataSheet: View {
    let profileName: String
    let clear: (ClearRange) -> Void
    let cancel: () -> Void
    @State private var range: ClearRange?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clear history and website data of “\(profileName)”")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("""
                Removes the history and the website data (logins, cookies and site storage) of “\(profileName)” for the \
                range you choose. Other Profiles are not touched, and neither are this Profile’s Spaces, Tabs and \
                settings. Open pages stay open and are not reloaded, but they lose what they stored, so they may ask \
                you to sign in again. This cannot be undone.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("Time range", selection: $range) {
                ForEach(ClearRange.allCases, id: \.self) { range in
                    Text(range.title).tag(Optional(range))
                }
            }
            .pickerStyle(.radioGroup)
            .accessibilityHint("Choose how far back to clear. Nothing is chosen until you pick one.")
            // A radio group takes the keyboard only with Full Keyboard Access, so the number keys choose a range too.
            Text("Press 1, 2 or 3 to choose a range, then Return.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle, role: .destructive) { range.map(clear) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(range == nil)
                    .accessibilityLabel(range.map { String(localized: "Clear \($0.title) of “\(profileName)”", comment: "Clear history and website data sheet") }
                        ?? String(localized: "Clear", comment: "Clear history and website data sheet"))
            }
        }
        .padding(20)
        .frame(width: 420)
        .background {
            ZStack {
                ForEach(Array(ClearRange.allCases.enumerated()), id: \.element) { index, option in
                    Button(option.title) { range = option }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [])
                }
            }
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var confirmTitle: String {
        range.map { String(localized: "Clear \($0.title)", comment: "Clear history and website data sheet") } ?? String(localized: "Clear", comment: "Clear history and website data sheet")
    }
}
