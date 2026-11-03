// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Commands

/// What the user picks during onboarding. Nothing is preselected: every choice starts empty.
public struct OnboardingChoices: Hashable, Sendable {
    public var shortcutPreset: ShortcutPreset?

    public init(shortcutPreset: ShortcutPreset? = nil) {
        self.shortcutPreset = shortcutPreset
    }
}
