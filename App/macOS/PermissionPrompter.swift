// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore

/// Asks the user whether a site may use the camera, the microphone or the location, or whether a link may open an
/// app, one question at a time, as a sheet on the Main window. It names the Profile as well as the site: an inactive
/// Profile's page can ask too.
@MainActor
final class PermissionPrompter {
    private let window: () -> NSWindow?
    private let profileName: (ProfileID) -> String
    /// A Private window's prompter: a choice is remembered only until the window closes.
    private let isPrivate: Bool
    private var tail: Task<Void, Never>?

    init(window: @escaping () -> NSWindow?, profileName: @escaping (ProfileID) -> String, isPrivate: Bool = false) {
        self.window = window
        self.profileName = profileName
        self.isPrivate = isPrivate
    }

    func ask(_ prompt: PermissionPrompt) async -> PermissionAnswer {
        await inTurn { await $0.show(prompt) }
    }

    /// "Open in Mail?" The safe answer is the default button: a user typing when the question appears could press
    /// Return by accident.
    func confirmOpen(_ prompt: AppLinkPrompt) async -> PermissionAnswer {
        await inTurn { await $0.show(prompt) }
    }

    /// Tells the user that no app takes the link.
    func refuseOpen(_ refusal: AppLinkRefusal) async {
        await inTurn { await $0.show(refusal) }
    }

    /// Tells the user that the app they chose could not open the link.
    func reportOpenFailure(of app: ExternalApp) async {
        await inTurn { await $0.show(failureOf: app) }
    }

    private func inTurn<Result: Sendable>(_ work: @escaping @MainActor (PermissionPrompter) async -> Result) async -> Result {
        let previous = tail
        let turn = Task { @MainActor in
            await previous?.value
            return await work(self)
        }
        tail = Task { _ = await turn.value }
        return await turn.value
    }

    private func show(_ prompt: PermissionPrompt) async -> PermissionAnswer {
        let alert = NSAlert()
        alert.messageText = Self.question(for: prompt)
        alert.informativeText = isPrivate
            ? String(localized: "This is a Private window. Nothing is kept once it closes.")
            : String(localized: """
                This is the Profile “\(profileName(prompt.profileID))”. Another Profile is asked on its own.
                """)
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Don’t Allow")).keyEquivalent = "\u{1b}"
        let remember = NSButton(
            checkboxWithTitle: isPrivate ? String(localized: "Remember my choice for this site until this window closes")
                                         : String(localized: "Remember my choice for this site in this Profile"),
            target: nil, action: nil)
        remember.sizeToFit()
        alert.accessoryView = remember
        let response = await present(alert)
        return PermissionAnswer(decision: response == .alertFirstButtonReturn ? .allow : .deny,
                                remember: remember.state == .on)
    }

    private func show(_ prompt: AppLinkPrompt) async -> PermissionAnswer {
        let alert = NSAlert()
        alert.messageText = String(localized: "Open in \(prompt.app.name)?")
        let scheme = prompt.scheme.rawValue
        let source = prompt.requestedBy.map { String(localized: "“\($0)” wants to open a “\(scheme):” link.") }
            ?? String(localized: "A page wants to open a “\(scheme):” link.")
        let profile = isPrivate
            ? String(localized: "This is a Private window. Nothing is kept once it closes.")
            : String(localized: "This is the Profile “\(profileName(prompt.profileID))”. Another Profile is asked on its own.")
        alert.informativeText = source + " " + profile
        alert.addButton(withTitle: String(localized: "Don’t Open"))
        alert.addButton(withTitle: String(localized: "Open"))
        let remember = NSButton(
            checkboxWithTitle: isPrivate
                ? String(localized: "Remember my choice for “\(scheme):” links until this window closes")
                : String(localized: "Remember my choice for “\(scheme):” links in this Profile"),
            target: nil, action: nil)
        remember.sizeToFit()
        alert.accessoryView = remember
        let response = await present(alert)
        return PermissionAnswer(decision: response == .alertSecondButtonReturn ? .allow : .deny,
                                remember: remember.state == .on)
    }

    private func show(_ refusal: AppLinkRefusal) async {
        let alert = NSAlert()
        alert.messageText = String(localized: "No app can open “\(refusal.scheme.rawValue):” links.")
        alert.informativeText = String(localized: "Nothing was opened. No app on this Mac is set up for this kind of link.")
        alert.addButton(withTitle: String(localized: "OK"))
        _ = await present(alert)
    }

    private func show(failureOf app: ExternalApp) async {
        let alert = NSAlert()
        alert.messageText = String(localized: "\(app.name) could not open the link.")
        alert.addButton(withTitle: String(localized: "OK"))
        _ = await present(alert)
    }

    private func present(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let window = window(), window.isVisible {
            return await alert.beginSheetModal(for: window)
        }
        return alert.runModal()
    }

    static func question(for prompt: PermissionPrompt) -> String {
        let site = prompt.origin.host
        let kinds = Set(prompt.kinds)
        if kinds == [.camera, .microphone] {
            return String(localized: "“\(site)” wants to use your camera and microphone.")
        }
        guard let kind = prompt.kinds.first, kinds.count == 1 else {
            return String(localized: "“\(site)” wants to use your camera, microphone or location.")
        }
        switch kind {
        case .camera: return String(localized: "“\(site)” wants to use your camera.")
        case .microphone: return String(localized: "“\(site)” wants to use your microphone.")
        case .location: return String(localized: "“\(site)” wants to know your location.")
        }
    }
}
