// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import SafiraCore
import SafiraWeb
import SwiftUI

/// What the sidebar asks the window to do with Profiles: the window owns the sheets and alerts, so that the menu and
/// the sidebar open the same ones.
struct ProfileActions {
    let select: (ProfileID) -> Void
    /// Opens the Profile editor: for a new Profile when the identifier is nil.
    let edit: (ProfileID?) -> Void
    /// Asks, naming the Profile, before deleting it.
    let delete: (ProfileID) -> Void
    /// Asks which range of the Profile's history and website data to clear.
    let clearBrowsingData: (ProfileID) -> Void
}

/// Names a new Profile or edits one, and picks its Theme from the Palette: the Profile's tint and Dock icon. A new
/// Profile needs a search engine, picked from a list where nothing is selected until the user chooses (decision D10).
struct ProfileEditor: View {
    let title: String
    let confirmTitle: String
    @State var name: String
    @State var symbol: String
    @State var paletteID: String
    let asksForSearchEngine: Bool
    let save: (_ name: String, _ symbol: String, _ paletteID: String, _ engine: SearchEngine?) -> Void
    let cancel: () -> Void
    @State private var engine: SearchEngine?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!asksForSearchEngine || engine != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Form {
                TextField("Name", text: $name)
                TextField("Symbol", text: $symbol)
                LabeledContent("Theme") { PalettePicker(selection: $paletteID) }
                if asksForSearchEngine {
                    Picker("Search engine", selection: $engine) {
                        ForEach(SearchEngine.allCases, id: \.self) { engine in
                            Text(engine.name).tag(Optional(engine))
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
            }
            if asksForSearchEngine {
                Text("The search engine belongs to this Profile only. Nothing is chosen for you.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(confirmTitle) { save(name, symbol, paletteID, engine) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
