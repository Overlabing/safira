// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands
import Onboarding
import SafiraCore
import SwiftUI

/// The first-launch onboarding: one step at a time, Return continues and nothing is applied before Finish. Every
/// choice is a list or a field that the arrow keys and Tab reach, so no step needs the mouse.
struct OnboardingView: View {
    let model: OnboardingModel
    let isDefaultBrowser: () -> Bool
    let makeDefaultBrowser: () -> Void

    private enum Focus { case name, list }
    @FocusState private var focus: Focus?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                Button("Back") { model.back() }
                    .disabled(model.isFirstStep)
                Spacer()
                if model.isLastStep {
                    Button("Finish") { model.finish() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.choices.isComplete)
                } else {
                    Button("Continue") { model.next() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canContinue)
                }
            }
        }
        .padding(20)
        .frame(width: 600, height: 640)
        // The controls of a step exist only after it is drawn, and a sheet takes the focus a moment after it opens.
        .task(id: model.step) {
            try? await Task.sleep(for: .milliseconds(150))
            focusFirstControl()
        }
    }

    private func focusFirstControl() {
        switch model.step {
        case .profile: focus = .name
        case .searchEngine, .shortcuts, .defaults: focus = .list
        case .welcome, .defaultBrowser: focus = nil
        }
    }

    private var title: LocalizedStringKey {
        switch model.step {
        case .welcome: "Welcome to Safira"
        case .profile: "Create your first Profile"
        case .searchEngine: "Choose a search engine"
        case .shortcuts: "Choose a Shortcut preset"
        case .defaultBrowser: "Make Safira your default browser?"
        case .defaults: "Everything Safira decided for you"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Text("Safira keeps your Profiles apart: each has its own logins, history and settings. In a few steps you create the first one, choose a search engine and a set of shortcuts, and see every default Safira picked, each of which you can change.")
                Text(Self.reminder).fontWeight(.semibold)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .profile:
            Form {
                TextField("Name", text: Bindable(model).profileName)
                    .focused($focus, equals: .name)
                TextField("Symbol", text: Bindable(model).profileSymbol)
            }
        case .searchEngine:
            VStack(alignment: .leading, spacing: 8) {
                Text("Nothing is chosen for you. Use ↑ and ↓ to move through the list, then Return to continue.")
                    .fixedSize(horizontal: false, vertical: true)
                List(SearchEngine.allCases, id: \.self, selection: Bindable(model).searchEngine) { engine in
                    Text(engine.name)
                }
                .focused($focus, equals: .list)
                .accessibilityLabel("Search engine")
                Text("The search engine belongs to this Profile only. Without one, the Command bar would ask at your first search.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .shortcuts:
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick the set of shortcuts you already know. Continue without picking to keep Safira's own shortcuts. You can change any shortcut later in Safira > Shortcuts.")
                    .fixedSize(horizontal: false, vertical: true)
                List(ShortcutPreset.allCases, id: \.self, selection: Bindable(model).shortcutPreset) { preset in
                    Text(preset.data.name)
                }
                .focused($focus, equals: .list)
                .accessibilityLabel("Shortcut preset")
            }
        case .defaultBrowser:
            VStack(alignment: .leading, spacing: 12) {
                Text("When Safira is your default browser, links from other apps come to it, and the Link picker asks which Profile receives each one, unless a Link rule decides. macOS asks you to confirm, and you can skip this and do it later from the Safira menu.")
                    .fixedSize(horizontal: false, vertical: true)
                Button(isDefaultBrowser() ? "Safira Is the Default Browser" : "Make Safira the Default Browser…",
                       action: makeDefaultBrowser)
                    .disabled(isDefaultBrowser())
            }
        case .defaults:
            VStack(alignment: .leading, spacing: 8) {
                Text("Use ↑ and ↓ to move and Space to flip a switch. Changes apply when you finish. \(Self.reminder)")
                    .fixedSize(horizontal: false, vertical: true)
                DefaultsListView(model: model.defaults)
                    .focused($focus, equals: .list)
            }
        }
    }

    static let reminder = String(localized: "Nothing is sent anywhere without an action of yours: Safira has no telemetry, does not check for updates, and does not send what you type for suggestions.")
}
