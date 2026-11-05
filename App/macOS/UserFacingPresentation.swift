// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import AppKit
import Preferences
import SafiraCore
import SwiftUI
import UserFacing

/// Shows an error of AppSupportKit's model as an alert. OK comes first and is the default button, then the error's action,
/// then Copy Details when the error has a technical detail, which the alert does not show. An `openURL` action opens its
/// page; any other action goes to `perform`. Banners are the Main window's (`MainWindowController.showBanner`).
@MainActor
enum UserFacingAlert {
    typealias Perform = @MainActor (UserFacingError.Action) -> Void

    /// App-modal: returns once the user has answered.
    static func runModal(_ error: UserFacingError, perform: Perform = { _ in }) {
        answer(make(error).runModal(), to: error, perform: perform)
    }

    /// A sheet on `window` when it is on screen, app-modal otherwise.
    static func show(_ error: UserFacingError, on window: NSWindow?, perform: Perform = { _ in }) async {
        let alert = make(error)
        let response = if let window, window.isVisible {
            await alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
        answer(response, to: error, perform: perform)
    }

    private static func make(_ error: UserFacingError) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = error.title
        alert.informativeText = error.message
        alert.addButton(withTitle: String(localized: "OK", comment: "Alert button"))
        if let action = error.action { alert.addButton(withTitle: action.title) }
        if error.canCopyDetails { alert.addButton(withTitle: String(localized: "Copy Details", comment: "Alert button")) }
        return alert
    }

    private static func answer(_ response: NSApplication.ModalResponse, to error: UserFacingError, perform: Perform) {
        let actions: [UserFacingError.Action?] = [nil] + (error.action.map { [$0] } ?? [])
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if index == actions.count, error.canCopyDetails {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(error.copiedDetails, forType: .string)
        } else if actions.indices.contains(index), let action = actions[index] {
            if let url = action.url { NSWorkspace.shared.open(url) } else { perform(action) }
        }
    }
}

/// An error of AppSupportKit's model shown in place, in a window or a form: what happened, what to do, and its action.
struct InlineErrorView: View {
    let error: UserFacingError
    let perform: (UserFacingError.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.title, systemImage: error.symbol)
                .symbolVariant(.fill)
                .font(.headline)
                .foregroundStyle(.orange)
            Text(error.message)
                .fixedSize(horizontal: false, vertical: true)
            if let action = error.action {
                Button(action.title) { perform(action) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// The saved settings that could not be read at launch. Each store has already put its default back; the first problem
/// is told once, in the Main window's banner.
@MainActor
final class PreferenceProblems {
    private var first: PreferenceError?

    func record(_ problem: PreferenceError) {
        if first == nil { first = problem }
    }

    func take() -> UserFacingError? {
        defer { first = nil }
        return first?.userFacingError
    }
}
