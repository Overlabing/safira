// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

import Onboarding
import Testing

@Test func noShortcutPresetIsPreselected() {
    #expect(OnboardingChoices().shortcutPreset == nil)
}
