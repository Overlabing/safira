// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import SwiftUI

/// Asked on the first search of a Profile that has no search engine. Nothing is preselected, and no engine is the
/// default button: the user always picks one explicitly.
struct SearchEnginePicker: View {
    let query: String
    let choose: (SearchEngine) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a search engine")
                .font(.headline)
            Text("This Profile has no search engine yet. Pick one to search for “\(query)”.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SearchEngine.allCases, id: \.self) { engine in
                    Button(engine.name) { choose(engine) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
