// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Antonin Carlin

/// A named set of keyboard shortcuts, chosen at onboarding.
public enum ShortcutPreset: String, CaseIterable, Sendable, Codable {
    case zen
    case arc
    case safari
}
