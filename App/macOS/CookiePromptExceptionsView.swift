// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import SafiraWeb
import SwiftUI

/// The sites of the Active profile whose cookie prompts Safira leaves alone, with a button to answer them again.
/// Sites are added from the address field's cookie indicator.
struct CookiePromptExceptionsView: View {
    let profile: ProfileContext

    var body: some View {
        let exceptions = profile.webContentSettings.cookiePrompts.exceptions.sorted()
        VStack(alignment: .leading, spacing: 8) {
            Text("Sites that keep their cookie prompts")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Text("Safira leaves these sites’ prompts for you to answer. Add a site from the cookie icon in the address field.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if exceptions.isEmpty {
                Text("No site keeps its cookie prompts in this Profile.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .settingsGroup()
            } else {
                List {
                    ForEach(exceptions, id: \.self) { site in
                        HStack {
                            Text(verbatim: site)
                            Spacer()
                            Button("Reject Again") { profile.webContentSettings.cookiePrompts.removeException(site) }
                                .accessibilityLabel(Text("Reject cookie prompts again on \(site)"))
                        }
                    }
                }
                .listStyle(.plain)
                .settingsScrollEdges()
                .frame(minHeight: 88)
                .settingsGroup()
            }
        }
    }
}
