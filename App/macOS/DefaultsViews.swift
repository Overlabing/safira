// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Onboarding
import SafiraCore
import SwiftUI

/// What the Defaults window can do with the entries that are not switches. Onboarding has none of it: it has a step for
/// each of those choices.
struct DefaultsChoiceActions {
    let profileName: String
    let engine: Binding<SearchEngine?>
    let preset: Binding<ShortcutPreset?>
    let isDefaultBrowser: () -> Bool
    let makeDefaultBrowser: () -> Void
}

/// Every user-facing default: a switch where there is one, its value and where else it can be changed. The list moves
/// with the arrow keys and Space flips the selected switch, so it needs no mouse.
struct DefaultsListView: View {
    let model: DefaultsSummaryModel
    var actions: DefaultsChoiceActions?
    @State private var selection: String?

    var body: some View {
        List(model.entries, selection: $selection) { entry in
            row(entry)
                .tag(entry.id)
                .listRowSeparator(.visible)
        }
        .onKeyPress(.space) {
            guard let id = selection, model.entries.first(where: { $0.id == id })?.isSwitch == true else { return .ignored }
            model.setOn(!model.isOn(id), for: id)
            return .handled
        }
        .accessibilityLabel("Defaults")
        .onAppear { selection = selection ?? model.entries.first?.id }
    }

    @ViewBuilder
    private func row(_ entry: DefaultEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch entry.control {
            case .toggle:
                Toggle(entry.title, isOn: Binding(get: { model.isOn(entry.id) }, set: { model.setOn($0, for: entry.id) }))
                    .accessibilityHint(entry.explanation)
            case .choice where entry.id == "search.engine" && actions != nil:
                if let actions {
                    Picker("\(entry.title), for \(actions.profileName)", selection: actions.engine) {
                        Text("Not chosen").tag(SearchEngine?.none)
                        ForEach(SearchEngine.allCases, id: \.self) { Text($0.name).tag(Optional($0)) }
                    }
                    .accessibilityHint(entry.explanation)
                }
            case .choice where entry.id == "shortcuts.preset" && actions != nil:
                if let actions {
                    Picker(entry.title, selection: actions.preset) {
                        Text("Safira's own shortcuts").tag(ShortcutPreset?.none)
                        ForEach(ShortcutPreset.allCases, id: \.self) { Text($0.data.name).tag(Optional($0)) }
                    }
                    .accessibilityHint(entry.explanation)
                }
            case .action where actions != nil:
                if let actions {
                    HStack {
                        Text(entry.title).font(.body)
                        Spacer()
                        Button(actions.isDefaultBrowser()
                               ? String(localized: "Safira Is the Default Browser", comment: "Disabled button: nothing left to do")
                               : String(localized: "Make Safira the Default Browser…", comment: "Button"),
                               action: actions.makeDefaultBrowser)
                            .disabled(actions.isDefaultBrowser())
                    }
                }
            default:
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title).font(.body)
                    Spacer()
                    Text(model.displayedValue(of: entry)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(entry.explanation)
            }
            Text(entry.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Default: \(entry.value). Change it: \(entry.whereToChange).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

private extension DefaultEntry {
    var isSwitch: Bool {
        if case .toggle = control { true } else { false }
    }
}

/// The Defaults window: the same list as the end of the onboarding, with each change applied as it is made.
struct DefaultsWindowView: View {
    let model: DefaultsSummaryModel
    let controller: DefaultsController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Defaults")
                .font(.title2.bold())
            Text("Everything Safira decided for you, and where to change it. Nothing is sent without an action of yours. Web content switches apply to \(controller.activeProfileName), and to pages opened from now on.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DefaultsListView(model: model, actions: DefaultsChoiceActions(
                profileName: controller.activeProfileName,
                engine: Binding(get: { controller.searchEngine }, set: { controller.searchEngine = $0 }),
                preset: Binding(get: { controller.shortcutPreset }, set: { controller.shortcutPreset = $0 }),
                isDefaultBrowser: controller.defaultBrowserActions.isDefault,
                makeDefaultBrowser: controller.defaultBrowserActions.make))
        }
        .padding(16)
        .frame(minWidth: 480, idealWidth: 600, minHeight: 400, idealHeight: 640)
    }
}
