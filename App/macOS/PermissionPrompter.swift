// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import SafiraCore

/// Asks the user whether a site may use the camera, the microphone or the location, one question at a time, as a
/// sheet on the Main window. It names the Profile as well as the site: an inactive Profile's page can ask too.
@MainActor
final class PermissionPrompter {
    private let window: () -> NSWindow?
    private let profileName: (ProfileID) -> String
    private var tail: Task<Void, Never>?

    init(window: @escaping () -> NSWindow?, profileName: @escaping (ProfileID) -> String) {
        self.window = window
        self.profileName = profileName
    }

    func ask(_ prompt: PermissionPrompt) async -> PermissionAnswer {
        let previous = tail
        let answer = Task { @MainActor in
            await previous?.value
            return await show(prompt)
        }
        tail = Task { _ = await answer.value }
        return await answer.value
    }

    private func show(_ prompt: PermissionPrompt) async -> PermissionAnswer {
        let alert = NSAlert()
        alert.messageText = Self.question(for: prompt)
        alert.informativeText = String(localized: """
            This is the Profile “\(profileName(prompt.profileID))”. Another Profile is asked on its own.
            """)
        alert.addButton(withTitle: String(localized: "Allow"))
        alert.addButton(withTitle: String(localized: "Don’t Allow")).keyEquivalent = "\u{1b}"
        let remember = NSButton(checkboxWithTitle: String(localized: "Remember my choice for this site in this Profile"),
                                target: nil, action: nil)
        remember.sizeToFit()
        alert.accessoryView = remember
        let response: NSApplication.ModalResponse
        if let window = window(), window.isVisible {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        return PermissionAnswer(decision: response == .alertFirstButtonReturn ? .allow : .deny,
                                remember: remember.state == .on)
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
