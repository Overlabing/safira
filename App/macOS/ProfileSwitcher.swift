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
}

/// The Active profile at the top of the sidebar, a menu that switches Profile. It is a different control, at the other
/// end of the sidebar, from the row of Spaces, so that a Profile never changes by accident.
struct ProfileSwitcher: View {
    let registry: ProfileRegistry
    let actions: ProfileActions

    var body: some View {
        Menu {
            ForEach(registry.profiles) { profile in
                Toggle(isOn: Binding(get: { registry.activeProfileID == profile.id },
                                     set: { if $0 { actions.select(profile.id) } })) {
                    Text(verbatim: "\(profile.symbol) \(profile.name)")
                }
            }
            Divider()
            Button("New Profile…") { actions.edit(nil) }
            Button("Rename Profile…") { actions.edit(registry.activeProfileID) }
            Button("Delete Profile…") { actions.delete(registry.activeProfileID) }
                .disabled(!registry.canDeleteProfile)
        } label: {
            Text(verbatim: "\(registry.activeProfile.symbol) \(registry.activeProfile.name)")
                .font(.headline)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .help("Switch Profile")
        .accessibilityLabel(String(localized: "Profile: \(registry.activeProfile.name)"))
        .accessibilityHint("Opens the list of Profiles")
    }
}

/// Names a new Profile or renames one. A new Profile needs a search engine, picked from a list where nothing is
/// selected until the user chooses (decision D10).
struct ProfileEditor: View {
    let title: String
    let confirmTitle: String
    @State var name: String
    @State var symbol: String
    let asksForSearchEngine: Bool
    let save: (_ name: String, _ symbol: String, _ engine: SearchEngine?) -> Void
    let cancel: () -> Void
    @State private var engine: SearchEngine?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!asksForSearchEngine || engine != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Form {
                TextField("Name", text: $name)
                TextField("Symbol", text: $symbol)
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
                Button(confirmTitle) { save(name, symbol, engine) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
