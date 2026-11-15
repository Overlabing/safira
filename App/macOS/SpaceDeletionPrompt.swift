// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Appearance
import AppShellKit
import Observation
import SafiraCore
import SafiraSession
import SafiraSettings
import SwiftUI

/// What the sidebar asks the window to do with Spaces: the window owns the sheets and the confirmation, so that the
/// menu, the Space rail and the editor open the same ones.
struct SpaceActions {
    /// Opens the Space editor: for a new Space when the identifier is nil.
    let edit: (SpaceID?) -> Void
    /// Asks before deleting a Space.
    let delete: (SpaceID) -> Void
}

/// The Space deletion the Main window is asking to confirm, and the Profile that holds the Space. AppShellKit's
/// confirmation is drawn by the window's backdrop, the one view that is there whatever the sidebar shows.
@MainActor
@Observable
final class SpaceDeletionPrompt {
    var pending: SpaceDeletion<SpaceID>?
    private var owner: ProfileSession?

    func ask(_ deletion: SpaceDeletion<SpaceID>, in owner: ProfileSession) {
        self.owner = owner
        pending = deletion
    }

    fileprivate func delete(_ id: SpaceID) {
        owner?.deleteSpace(id)
        owner = nil
    }
}

extension View {
    /// Shows AppShellKit's Delete Space confirmation while `prompt` has one pending.
    func spaceDeletionPrompt(_ prompt: SpaceDeletionPrompt) -> some View {
        modifier(SpaceDeletionPromptModifier(prompt: prompt))
    }
}

private struct SpaceDeletionPromptModifier: ViewModifier {
    @Bindable var prompt: SpaceDeletionPrompt

    func body(content: Content) -> some View {
        content.spaceDeletionConfirmation($prompt.pending, palette: ThemeCatalog.palette) { id, _ in
            prompt.delete(id)
        }
    }
}
