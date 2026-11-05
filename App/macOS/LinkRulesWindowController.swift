// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import LinkRouting
import SafiraCore
import SwiftUI
import UniformTypeIdentifiers

/// The Link rules window: the rules in order with delete and reorder, import and export, and the check "Where would
/// this link go?".
@MainActor
final class LinkRulesWindowController: NSWindowController, NSWindowDelegate {
    let model: LinkRulesModel
    private let rulesFile: URL
    private let profiles: @MainActor () -> [Profile]

    init(model: LinkRulesModel, rulesFile: URL, profiles: @escaping @MainActor () -> [Profile]) {
        self.model = model
        self.rulesFile = rulesFile
        self.profiles = profiles
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = String(localized: "Link Rules", comment: "Link rules window")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 600, height: 540)
        window.isRestorable = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView: LinkRulesView(model: model, actions: LinkRulesActions(
            importFile: { [weak self] in self?.importFile() }, importZenPicker: { [weak self] in self?.importZenPicker() },
            export: { [weak self] in self?.export() }, showInFinder: { [weak self] in self?.showInFinder() })))
        // The hosting controller sizes the window to the view's minimum, which would clip the check's answer.
        window.setContentSize(NSSize(width: 680, height: 620))
        window.setFrameAutosaveName("LinkRulesWindow")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc func show(_ sender: Any?) {
        model.reload()
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        NSApp.activate()
    }

    /// The file may have been edited by hand while the window was in the background.
    func windowDidBecomeKey(_ notification: Notification) {
        model.reload()
    }

    // MARK: - Files

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([rulesFile])
    }

    private func export() {
        guard let data = model.exportData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "link-rules.json"
        panel.message = String(localized: "Save your Link rules as a JSON file.", comment: "Link rules window")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            alert(String(localized: "The Link rules could not be saved", comment: "Link rules window"), error.localizedDescription)
        }
    }

    private func importFile() {
        guard let data = pickFile(message: String(localized: "Choose a Link rules JSON file to import.", comment: "Link rules window")) else { return }
        // An invalid file is reported before the user is asked how to import it.
        if case .failure(let error) = LinkRuleSet.parse(data) {
            alert(String(localized: "That file is not a valid Link rules file", comment: "Link rules window"),
                  error.explanation + " " + String(localized: "Your existing rules were not changed.", comment: "Link rules window"))
            return
        }
        let imported = (try? LinkRuleSet.parse(data).get().rules.count) ?? 0
        let existing = model.entries.count
        let ask = NSAlert()
        ask.messageText = String(localized: "Import \(imported) rules", comment: "Link rules window")
        ask.informativeText = existing == 0
            ? String(localized: "Your Link rules are empty, so the imported rules become your rules.", comment: "Link rules window")
            : String(localized: "Add them after your \(existing) rules, which keep winning, or replace your rules with the imported ones.", comment: "Link rules window")
        ask.addButton(withTitle: existing == 0 ? String(localized: "Import", comment: "Link rules window") : String(localized: "Add to the End", comment: "Link rules window"))
        if existing > 0 { ask.addButton(withTitle: String(localized: "Replace My Rules", comment: "Link rules window")) }
        ask.addButton(withTitle: String(localized: "Cancel", comment: "Link rules window"))
        let answer = ask.runModal()
        if answer == .alertFirstButtonReturn {
            model.importFile(data, mode: .addToEnd)
        } else if existing > 0, answer == .alertSecondButtonReturn {
            model.importFile(data, mode: .replace)
        }
    }

    private func importZenPicker() {
        guard let data = pickFile(message: String(localized: "Choose a ZenPicker rules.json file to import.", comment: "Link rules window")) else { return }
        let targets: [String]
        switch model.zenPickerTargets(in: data) {
        case .failure(let error):
            alert(String(localized: "That is not a ZenPicker rules file", comment: "Link rules window"),
                  error.explanation + " " + String(localized: "Your existing rules were not changed.", comment: "Link rules window"))
            return
        case .success(let found): targets = found
        }
        let profiles = profiles()
        guard !targets.isEmpty else {
            alert(String(localized: "Nothing to import", comment: "Link rules window"), String(localized: "The file has no rule that names a target.", comment: "Link rules window"))
            return
        }
        let popups = targets.map { target -> (target: String, popup: NSPopUpButton) in
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItem(withTitle: String(localized: "Do not import", comment: "Link rules window"))
            popup.menu?.addItem(.separator())
            for profile in profiles { popup.addItem(withTitle: "\(profile.symbol) \(profile.name)") }
            popup.setAccessibilityLabel(String(localized: "Profile for the target \(target)", comment: "Link rules window"))
            return (target, popup)
        }
        let rows = popups.map { entry -> NSView in
            let label = NSTextField(labelWithString: entry.target)
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
            let row = NSStackView(views: [label, entry.popup])
            row.spacing = 10
            return row
        }
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 360, height: CGFloat(rows.count) * 30)
        let ask = NSAlert()
        ask.messageText = String(localized: "Which Profile should each target open in?", comment: "Link rules window")
        ask.informativeText = String(localized: "ZenPicker sends links to a target. Choose the Safira Profile that replaces each one. The rules are added after your own.", comment: "Link rules window")
        ask.accessoryView = stack
        ask.addButton(withTitle: String(localized: "Import", comment: "Link rules window"))
        ask.addButton(withTitle: String(localized: "Cancel", comment: "Link rules window"))
        guard ask.runModal() == .alertFirstButtonReturn else { return }
        var mapping: [String: ProfileID] = [:]
        for (target, popup) in popups where popup.indexOfSelectedItem >= 2 {
            mapping[target] = profiles[popup.indexOfSelectedItem - 2].id
        }
        model.importZenPicker(data, profileFor: mapping)
    }

    private func pickFile(message: String) -> Data? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = message
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            alert(String(localized: "The file could not be read", comment: "Link rules window"), "")
            return nil
        }
        return data
    }

    private func alert(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.runModal()
    }
}

struct LinkRulesActions {
    let importFile: () -> Void
    let importZenPicker: () -> Void
    let export: () -> Void
    let showInFinder: () -> Void
}

private struct LinkRulesView: View {
    @Bindable var model: LinkRulesModel
    let actions: LinkRulesActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Link rules send a link to a Profile without asking. The first rule that matches wins.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let problem = model.fileProblem {
                invalidFile(problem)
            } else {
                list
                toolbar
            }
            statusLine
            Divider()
            check
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 540)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var list: some View {
        List(selection: $model.selection) {
            ForEach(model.entries) { entry in
                row(entry)
                    .tag(entry.position)
            }
        }
        .listStyle(.bordered)
        .frame(minHeight: 200)
        .overlay {
            if model.entries.isEmpty {
                Text("No Link rules yet. Choose “Always” in the Link picker, or import a file.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .onDeleteCommand { model.deleteSelected() }
        .accessibilityLabel(Text("Link rules"))
        // The overlay that says the list is empty is not part of the list's accessibility tree.
        .accessibilityValue(model.entries.isEmpty
            ? Text("No Link rules yet. Choose “Always” in the Link picker, or import a file.") : Text(verbatim: ""))
    }

    private func row(_ entry: LinkRuleEntry) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(entry.position)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.match).fontWeight(.medium)
                if let problem = entry.problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            Text(verbatim: entry.destination)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if entry.rule.forcesNewTab {
                Image(systemName: "plus.square.on.square").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.accessibilityLabel)
        .accessibilityAddTraits(model.selection == entry.position ? .isSelected : [])
        .accessibilityAction(named: Text("Move Up")) { model.selection = entry.position; model.moveSelected(by: -1) }
        .accessibilityAction(named: Text("Move Down")) { model.selection = entry.position; model.moveSelected(by: 1) }
        .accessibilityAction(named: Text("Delete")) { model.selection = entry.position; model.deleteSelected() }
    }

    private var toolbar: some View {
        HStack {
            Button("Move Up") { model.moveSelected(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: .option)
                .disabled(!model.canMoveUp)
                .help("Move the selected rule up (⌥↑)")
            Button("Move Down") { model.moveSelected(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: .option)
                .disabled(!model.canMoveDown)
                .help("Move the selected rule down (⌥↓)")
            Button("Delete", role: .destructive) { model.deleteSelected() }
                .disabled(model.selectedEntry == nil)
                .help("Delete the selected rule (Delete)")
            Spacer()
            Menu("Import") {
                Button("Link Rules File…", action: actions.importFile)
                Button("ZenPicker Rules…", action: actions.importZenPicker)
            }
            .fixedSize()
            Button("Export…", action: actions.export)
            Button("Show in Finder", action: actions.showInFinder)
        }
    }

    private func invalidFile(_ problem: LinkRulesError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The Link rules file is not valid", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(verbatim: problem.explanation)
            Text("Safira never overwrites it. No rule applies until it is fixed: links go to the Link picker. Fix it in an editor, or delete it to start again.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Show in Finder", action: actions.showInFinder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.fileProblem == nil, let message = model.message {
            Text(verbatim: message.text)
                .foregroundStyle(message.isError ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(Text(verbatim: message.text))
                .onChange(of: message) { _, new in announce(new.text) }
        }
    }

    private var check: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where would this link go?").font(.headline)
            HStack {
                TextField("Link", text: $model.checkedAddress, prompt: Text("Paste a link to check"))
                    .accessibilityLabel(Text("Link to check"))
                    .onSubmit { runCheck() }
                TextField("Opener", text: $model.checkedOpener, prompt: Text("Opener (optional), such as com.example.chat"))
                    .accessibilityLabel(Text("Opener bundle identifier, optional"))
                    .frame(maxWidth: 240)
                    .onSubmit { runCheck() }
                Button("Check", action: runCheck)
            }
            if let result = model.checkResult {
                Text(verbatim: result)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }

    private func runCheck() {
        model.runCheck()
        if let result = model.checkResult { announce(result) }
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}
